class Pic2LinkResubmission < Pic2LinkRelease
  OUTPUT = File.join(ROOT, "dist/mas-build2-20260911")
  OLD_SUBMISSION = "91bfa1ba-ec2e-4072-bab1-767635cdb192"

  def run(stage)
    raise "Target mismatch" unless ENV["CONFIRM_PIC2LINK_BUILD2"] == "6809069103|Amanoya.Pic2Link|MAC_OS|1.0.1|2|AFTER_APPROVAL"
    raise "Version mismatch" unless version.dig("attributes", "versionString") == "1.0.1"
    case stage
    when "inspect" then inspect_current
    when "wait" then wait_build
    when "metadata" then update_descriptions
    when "prepare" then prepare_build
    when "submit" then resubmit
    when "verify" then verify_resubmission
    else raise "Unknown stage"
    end
  end

  def wait_build
    20.times do
      builds = Spaceship::ConnectAPI::Build.all(app_id: APP_ID, version: "1.0.1", build_number: "2", platform: "MAC_OS")
      if builds.any?
        raise "Ambiguous build" unless builds.length == 1
        state = builds.first.processing_state
        puts "Build 2 processing: #{state}"
        raise "Apple rejected build processing" if %w[FAILED INVALID].include?(state)
        if state == "VALID"
          inspect_current
          return
        end
      end
      sleep 30
    end
    raise "Processing pending; inspect rather than reupload"
  end

  def save(name, data)
    FileUtils.mkdir_p(OUTPUT)
    File.write(File.join(OUTPUT, name + ".json"), JSON.pretty_generate(data))
  end

  def inspect_current
    submissions = all("v1/apps/#{APP_ID}/reviewSubmissions", {filter: {platform: "MAC_OS"}})
    result = {version: version["attributes"].slice("versionString", "appStoreState", "releaseType"),
      builds: all("v1/builds", {filter: {app: APP_ID}}).map { |b| {id: b["id"], attributes: b["attributes"].slice("version", "processingState", "usesNonExemptEncryption")} },
      submissions: submissions.map { |s| {id: s["id"], attributes: s["attributes"], items: all("v1/reviewSubmissions/#{s['id']}/items", {include: "appStoreVersion"})} }}
    save("current-state", result)
    puts JSON.pretty_generate(result)
  end

  def update_descriptions
    raise "Not editable" unless %w[REJECTED PREPARE_FOR_SUBMISSION].include?(version.dig("attributes", "appStoreState"))
    qa = JSON.parse(File.read(File.join(ROOT, "docs/release/review-description-qa.json")))
    raise "QA mismatch" unless qa["static_status"] == "pass" && qa["scoped_semantic_status"] == "pass"
    locales = all("v1/appStoreVersions/#{VERSION_ID}/appStoreVersionLocalizations")
    raise "Locale mismatch" unless locales.map { |l| l.dig("attributes", "locale") }.sort == LOCALES.sort
    locales.each do |l|
      locale = l.dig("attributes", "locale")
      path = File.join(ROOT, "fastlane/metadata", locale, "description.txt")
      raise "Stale QA" unless Digest::SHA256.file(path).hexdigest == qa["input_hashes"]["#{locale}/description.txt"]
      expected = File.read(path).strip
      patch("appStoreVersionLocalizations", l["id"], {description: expected}) unless l.dig("attributes", "description") == expected
      actual = get("v1/appStoreVersionLocalizations/#{l['id']}")["data"]["attributes"]
      raise "Description mismatch" unless actual["description"] == expected
      raise "Unrelated fields changed" unless l["attributes"].reject { |k,_| k == "description" }.all? { |k,v| actual[k] == v }
    end
    save("description-verification", {locales: LOCALES, verified: true, other_fields_preserved: true})
    puts "13 descriptions verified; other fields preserved"
  end

  def build2
    builds = Spaceship::ConnectAPI::Build.all(app_id: APP_ID, version: "1.0.1", build_number: "2", platform: "MAC_OS")
    raise "Build 2 not VALID" unless builds.length == 1 && builds.first.processing_state == "VALID"
    build = get("v1/builds/#{builds.first.id}")["data"]
    raise "Encryption mismatch" unless build.dig("attributes", "usesNonExemptEncryption") == false
    build
  end

  def prepare_build
    build = build2
    raise "Not editable" unless %w[REJECTED PREPARE_FOR_SUBMISSION].include?(version.dig("attributes", "appStoreState"))
    @client.patch_app_store_version_with_build(app_store_version_id: VERSION_ID, build_id: build["id"])
    review = get("v1/appStoreVersions/#{VERSION_ID}/appStoreReviewDetail")["data"]
    notes = review.dig("attributes", "notes").to_s
    raise "Missing tested review configuration" unless notes.include?("pic2link-review-20260911-92a7") && notes.include?("AccessKey Secret:")
    old = "This note provides the requested demo configuration for Guideline 2.1(a). It does not assert that the currently selected build has been replaced; the separate binary change addressing Guideline 2.4.5(i) must be uploaded before resubmission."
    replacement = "Build 1.0.1 (2) addresses both review issues. For Guideline 2.4.5(i), all temporary Apple Events entitlement exceptions have been removed. Finder selection automation is disabled in the Mac App Store build; please use drag-and-drop, clipboard upload, or the system file picker instead. Photos uses its public scripting access group and PhotoKit. For Guideline 2.1(a), the isolated OSS demo configuration above has been tested for connection, upload, and public image retrieval."
    raise "Unexpected review notes" unless notes.include?(old) || notes.include?(replacement)
    expected = notes.gsub(old, replacement)
    patch("appStoreReviewDetails", review["id"], {notes: expected}) unless expected == notes
    actual = get("v1/appStoreVersions/#{VERSION_ID}/appStoreReviewDetail")["data"]["attributes"]
    raise "Review readback mismatch" unless actual["notes"] == expected
    raise "Review fields changed" unless review["attributes"].reject { |k,_| k == "notes" }.all? { |k,v| actual[k] == v }
    patch("appStoreVersions", VERSION_ID, {releaseType: "AFTER_APPROVAL"})
    verify_ready
    save("preparation", {build_id: build["id"], notes_verified: true, release_type: "AFTER_APPROVAL"})
    puts "Build 2 and review notes verified"
  end

  def verify_ready
    build = build2
    raise "Wrong selected build" unless get("v1/appStoreVersions/#{VERSION_ID}/build").dig("data", "id") == build["id"]
    raise "Release mode mismatch" unless version.dig("attributes", "releaseType") == "AFTER_APPROVAL"
    raise "Unexpected phased release" if get("v1/appStoreVersions/#{VERSION_ID}/appStoreVersionPhasedRelease")["data"]
    verify_metadata
    verify_screenshots
    # Existing commerce evidence remains the baseline; never change prices here.
    verify_commerce
    info = app_info
    raise "Category changed" unless get("v1/appInfos/#{info['id']}/primaryCategory").dig("data", "id") == "PRODUCTIVITY"
    rating = get("v1/appInfos/#{info['id']}/ageRatingDeclaration")["data"]
    expected_rating = JSON.parse(File.read(File.join(REPORTS, "ratings-verification.json")))
    raise "Ratings changed" unless rating["attributes"] == expected_rating["attributes"]
    review = get("v1/appStoreVersions/#{VERSION_ID}/appStoreReviewDetail")["data"]
    raise "Review details incomplete" unless %w[contactFirstName contactLastName contactEmail contactPhone notes].all? { |k| !review.dig("attributes", k).to_s.empty? }
    raise "Missing reviewer configuration" unless review.dig("attributes", "notes").include?("pic2link-review-20260911-92a7")
    raise "Missing new-build explanation" unless review.dig("attributes", "notes").include?("Build 1.0.1 (2) addresses both review issues.")
    privacy = JSON.parse(File.read(File.join(REPORTS, "privacy-verification.json")))
    raise "Privacy not verified" unless privacy.dig("state", "data", "attributes", "published") == true
    build
  end

  def resubmit
    build = verify_ready
    active = all("v1/apps/#{APP_ID}/reviewSubmissions", {filter: {platform: "MAC_OS"}}).reject { |s| s.dig("attributes", "state") == "COMPLETE" }
    raise "Unrelated active submission" unless active.length == 1 && active.first["id"] == OLD_SUBMISSION
    submission = get("v1/reviewSubmissions/#{OLD_SUBMISSION}")["data"]
    items = all("v1/reviewSubmissions/#{OLD_SUBMISSION}/items", {include: "appStoreVersion"})
    raise "Unexpected review items" unless items.length == 1 && items.first.dig("relationships", "appStoreVersion", "data", "id") == VERSION_ID
    if submission.dig("attributes", "state") == "UNRESOLVED_ISSUES"
      # Apple's ReviewSubmissionItemUpdateRequest supports resolved=true.
      # Resolve only this app version after its new build and notes are verified.
      if items.first.dig("attributes", "state") == "REJECTED"
        patch("reviewSubmissionItems", items.first["id"], {resolved: true})
      end
      submission = get("v1/reviewSubmissions/#{OLD_SUBMISSION}")["data"]
      items = all("v1/reviewSubmissions/#{OLD_SUBMISSION}/items", {include: "appStoreVersion"})
    end
    # Resolving the item makes the item/version READY_FOR_REVIEW while the
    # enclosing rejected submission remains UNRESOLVED_ISSUES until submitted.
    raise "Inspect review submission state before continuing" unless %w[READY_FOR_REVIEW UNRESOLVED_ISSUES].include?(submission.dig("attributes", "state"))
    raise "Item is not ready" unless items.length == 1 && items.first.dig("attributes", "state") == "READY_FOR_REVIEW" && items.first.dig("relationships", "appStoreVersion", "data", "id") == VERSION_ID
    @client.patch_review_submission(review_submission_id: OLD_SUBMISSION, attributes: {submitted: true})
    inspect_current
  end

  def verify_resubmission
    build = build2
    selected = get("v1/appStoreVersions/#{VERSION_ID}/build")["data"]
    submission = get("v1/reviewSubmissions/#{OLD_SUBMISSION}")["data"]
    items = all("v1/reviewSubmissions/#{OLD_SUBMISSION}/items", {include: "appStoreVersion"})
    raise "Review not submitted" unless %w[WAITING_FOR_REVIEW IN_REVIEW].include?(submission.dig("attributes", "state"))
    raise "Wrong review item" unless items.length == 1 && items.first.dig("relationships", "appStoreVersion", "data", "id") == VERSION_ID
    raise "Wrong build" unless selected["id"] == build["id"]
    current = version
    raise "Wrong version state" unless %w[WAITING_FOR_REVIEW IN_REVIEW].include?(current.dig("attributes", "appStoreState"))
    raise "Wrong release mode" unless current.dig("attributes", "releaseType") == "AFTER_APPROVAL"
    raise "Phased release enabled" if get("v1/appStoreVersions/#{VERSION_ID}/appStoreVersionPhasedRelease")["data"]
    result = {app_id: APP_ID, bundle_id: BUNDLE_ID, platform: "MAC_OS", version: "1.0.1", build: "2", build_id: build["id"],
      build_state: "VALID", uses_non_exempt_encryption: false, submission_id: OLD_SUBMISSION,
      submission_state: submission.dig("attributes", "state"), version_state: current.dig("attributes", "appStoreState"),
      release_type: "AFTER_APPROVAL", phased_release: false, review_items: items.length, checked_at: Time.now.utc.iso8601}
    save("submission-verification", result)
    puts JSON.pretty_generate(result)
  end
end
