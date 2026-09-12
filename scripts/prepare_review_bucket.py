#!/usr/bin/env python3
"""Provision only Pic2Link's isolated review bucket; never print credentials.

Uses the existing codex CLI profile in memory. --apply authorizes creation of
the exact named bucket. RAM credentials are a separate administrator operation.
"""
import argparse
import base64
import email.utils
import hashlib
import hmac
import json
from pathlib import Path
import urllib.error
import urllib.request
import uuid
import xml.etree.ElementTree as ET

BUCKET = "pic2link-review-20260911-92a7"
REGION = "ap-southeast-1"
OWNER = "1945014481925631"
ENDPOINT = f"oss-{REGION}.aliyuncs.com"
ROOT = Path(__file__).resolve().parents[1]


def request(profile, method, query="", body=b"", key="", headers=None, content_type=None):
    date = email.utils.formatdate(usegmt=True)
    content_type = content_type or ("application/xml" if body else "")
    md5 = base64.b64encode(hashlib.md5(body).digest()).decode() if body else ""
    resource = f"/{BUCKET}/{key}" + (f"?{query}" if query else "")
    canonical = f"{method}\n{md5}\n{content_type}\n{date}\n{resource}"
    signature = base64.b64encode(hmac.new(profile["access_key_secret"].encode(), canonical.encode(), hashlib.sha1).digest()).decode()
    values = {"Date": date, "Authorization": f'OSS {profile["access_key_id"]}:{signature}'}
    if body:
        values.update({"Content-Type": content_type, "Content-MD5": md5})
    values.update(headers or {})
    url = f"https://{BUCKET}.{ENDPOINT}/{key}" + (f"?{query}" if query else "")
    req = urllib.request.Request(url, data=body if body else None, method=method, headers=values)
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        content = error.read()
        try:
            code = ET.fromstring(content).findtext("Code")
        except ET.ParseError:
            code = "UnknownError"
        return error.code, code.encode()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--verify-network", action="store_true")
    args = parser.parse_args()
    profiles = json.loads(Path("/Users/amano/.aliyun/config.json").read_text())["profiles"]
    profile = next(p for p in profiles if p["name"] == "codex")
    status, body = request(profile, "GET", "bucketInfo")
    existed = status == 200
    if not existed and not (status == 404 and body == b"NoSuchBucket"):
        raise SystemExit(f"Bucket inspection failed: HTTP {status}, {body.decode()}")
    if args.verify_network:
        assert existed and ET.fromstring(body).findtext(".//Owner/ID") == OWNER
        sample = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1sAAAAASUVORK5CYII=")
        key = f"review/verification-{uuid.uuid4()}.png"
        status, _ = request(profile, "PUT", body=sample, key=key, content_type="image/png")
        assert status == 200
        url = f"https://{BUCKET}.{ENDPOINT}/{key}"
        with urllib.request.urlopen(url, timeout=30) as response:
            assert response.status == 200 and response.read() == sample
            assert response.headers.get_content_type() == "image/png"
        try:
            urllib.request.urlopen(f"https://{BUCKET}.{ENDPOINT}/", timeout=30)
            raise AssertionError("Anonymous bucket listing must be forbidden")
        except urllib.error.HTTPError as error:
            assert error.code == 403
        report = {"synthetic_sample_url": url, "authenticated_upload": 200,
            "anonymous_get": 200, "anonymous_list": 403, "bytes_verified": True,
            "identity_used": "codex administrator; NOT the blocked reviewer account", "cleanup": "30-day lifecycle"}
        (ROOT / "dist/review-fix-20260911/network-verification.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report))
        return
    if not args.apply:
        print(json.dumps({"bucket": BUCKET, "region": REGION, "exists": existed}))
        return
    if existed:
        info = ET.fromstring(body)
        if info.findtext(".//Owner/ID") != OWNER:
            raise SystemExit("Existing bucket owner mismatch; no changes made")
        assert info.findtext(".//CreationDate", "").startswith("2026-09-11")
        # Only resume this task's empty bucket; never touch production objects.
        status, listing = request(profile, "GET")
        assert status == 200 and not ET.fromstring(listing).findall("Contents")
    else:
        config = f"<CreateBucketConfiguration><LocationConstraint>oss-{REGION}</LocationConstraint><StorageClass>Standard</StorageClass></CreateBucketConfiguration>".encode()
        status, _ = request(profile, "PUT", body=config)
        if status != 200:
            raise SystemExit(f"CreateBucket failed: HTTP {status}")
    # Default ACL remains private. Anonymous readers can GET review objects only,
    # never list the bucket or write objects.
    policy = {"Version": "1", "Statement": [{"Effect": "Allow", "Principal": ["*"],
        "Action": ["oss:GetObject"], "Resource": [f"acs:oss:*:*:{BUCKET}/review/*"]}]}
    status, current = request(profile, "GET", "policy")
    assert (status == 404 and current == b"NoSuchBucketPolicy") or (status == 200 and json.loads(current) == policy)
    # This is BUCKET-SCOPED only. Never disable account-level public access blocks.
    status, current = request(profile, "GET", "publicAccessBlock")
    assert status == 200
    if ET.fromstring(current).findtext("BlockPublicAccess") == "true":
        status, error = request(profile, "PUT", "publicAccessBlock",
            b"<PublicAccessBlockConfiguration><BlockPublicAccess>false</BlockPublicAccess></PublicAccessBlockConfiguration>")
        if status != 200:
            raise SystemExit(f"Bucket-scoped public read setup blocked: HTTP {status}, {error.decode()}")
    status, error = request(profile, "PUT", "policy", json.dumps(policy).encode())
    if status != 200:
        raise SystemExit(f"Bucket created, but policy failed: HTTP {status}, {error.decode()}; inspect before retrying")
    lifecycle = b"<LifecycleConfiguration><Rule><ID>review-samples-30-days</ID><Prefix>review/</Prefix><Status>Enabled</Status><Expiration><Days>30</Days></Expiration><AbortMultipartUpload><Days>1</Days></AbortMultipartUpload></Rule></LifecycleConfiguration>"
    status, _ = request(profile, "PUT", "lifecycle", lifecycle)
    if status != 200:
        raise SystemExit(f"Bucket created, but lifecycle failed: HTTP {status}; inspect before retrying")
    status, body = request(profile, "GET", "bucketInfo")
    assert status == 200
    info = ET.fromstring(body)
    assert info.findtext(".//Owner/ID") == OWNER
    assert info.findtext(".//AccessControlList/Grant") == "private"
    status, body = request(profile, "GET", "policy")
    assert status == 200 and json.loads(body) == policy
    status, body = request(profile, "GET", "lifecycle")
    assert status == 200 and ET.fromstring(body).findtext(".//Expiration/Days") == "30"
    report = {"bucket": BUCKET, "region": REGION, "endpoint": ENDPOINT,
        "publicURL": f"https://{BUCKET}.{ENDPOINT}", "basePath": "review", "acl": "private",
        "anonymousReadPrefix": "review/", "expirationDays": 30, "verified": True,
        "credentials": "BLOCKED: codex lacks ram:CreateUser", "billing": "Standard pay-as-you-go; no package purchased; no hard spending cap"}
    output = ROOT / "dist/review-fix-20260911"
    output.mkdir(parents=True, exist_ok=True)
    (output / "bucket-verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
