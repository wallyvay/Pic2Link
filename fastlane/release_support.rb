require "json"
require "digest"
require "logger"

class Pic2LinkRelease
  APP_ID = "6809069103".freeze
  VERSION_ID = "432a412d-0de5-4c5c-8a03-9114847ac44b".freeze
  BUNDLE_ID = "Amanoya.Pic2Link".freeze
  STORE_NAME = "Pic2Link: Image Uploader".freeze
  ROOT = File.expand_path("..", __dir__)
  REPORTS = File.join(ROOT, "dist/mas-20260905")
  LOCALES = %w[en-US zh-Hans zh-Hant ko ja ru es-ES pt-BR th hi fr-FR ar-SA de-DE].freeze

  def initialize(client = Spaceship::ConnectAPI)
    @client = client
    @api = client.tunes_request_client
    # Review notes can contain private demo credentials. Spaceship otherwise logs
    # JSON request/response bodies to /tmp, including those notes.
    @api.logger = Logger.new(File::NULL)
    app = get("v1/apps/#{APP_ID}")["data"]
    expected = {"bundleId" => BUNDLE_ID, "sku" => BUNDLE_ID, "primaryLocale" => "en-US", "name" => STORE_NAME}
    raise "App identity mismatch" unless expected.all? { |k,v| app["attributes"][k] == v }
    version = get("v1/appStoreVersions/#{VERSION_ID}")["data"]
    raise "Platform mismatch" unless version["attributes"]["platform"] == "MAC_OS"
    versions = all("v1/apps/#{APP_ID}/appStoreVersions")
    raise "Version belongs to another app" unless versions.any? { |v| v["id"] == VERSION_ID }
  end

  def get(path, params = {})
    @api.get(path, params).body
  end

  def all(path, params = {})
    @api.get(path, params).all_pages.flat_map { |r| r.body.fetch("data") }
  end

  def patch(type, id, attributes)
    @api.patch("v1/#{type}/#{id}", {data: {type: type, id: id, attributes: attributes}}).body
  end

  def save(name, data)
    File.write(File.join(REPORTS, name + ".json"), JSON.pretty_generate(data) + "\n")
  end

  def guard!
    expected = "#{APP_ID}|#{BUNDLE_ID}|MAC_OS|1.0.1|1|AFTER_APPROVAL"
    raise "Release target mismatch" unless ENV["CONFIRM_PIC2LINK_RELEASE"] == expected
  end

  def version
    get("v1/appStoreVersions/#{VERSION_ID}")["data"]
  end

  def app_info
    list = all("v1/apps/#{APP_ID}/appInfos")
    raise "Ambiguous app info" unless list.length == 1
    list.first
  end

  def inspect_details
    info = app_info
    snapshot = {checked_at: Time.now.utc.iso8601, app: get("v1/apps/#{APP_ID}")["data"], version: version,
      app_info: info, app_info_localizations: all("v1/appInfos/#{info['id']}/appInfoLocalizations"),
      version_localizations: all("v1/appStoreVersions/#{VERSION_ID}/appStoreVersionLocalizations"),
      age_rating: get("v1/appInfos/#{info['id']}/ageRatingDeclaration")["data"],
      review_submissions: all("v1/apps/#{APP_ID}/reviewSubmissions", {filter: {platform: "MAC_OS"}})}
    %W[v1/apps/#{APP_ID}/appPriceSchedule v1/apps/#{APP_ID}/appAvailabilityV2 v1/appStoreVersions/#{VERSION_ID}/appStoreReviewDetail v1/appStoreVersions/#{VERSION_ID}/appStoreVersionPhasedRelease].each do |path|
      begin
        snapshot[path.split('/').last] = get(path)
      rescue => error
        snapshot[path.split('/').last] = {error: error.message}
      end
    end
    save("asc-details", snapshot)
    puts "Read back #{APP_ID}: #{version['attributes']['versionString']} #{version['attributes']['appStoreState']}"
  end

  def upload_metadata
    guard!
    raise "Unexpected version" unless %w[1.0 1.0.1].include?(version["attributes"]["versionString"])
    patch("appStoreVersions", VERSION_ID, {versionString: "1.0.1", copyright: "2026 Li Wei", releaseType: "AFTER_APPROVAL"})
    info = app_info
    # Use the verified AppInfo endpoint for the category relationship.
    @client.patch_app_info_categories(app_info_id: info["id"], category_id_map: {primary_category_id: "PRODUCTIVITY"})
    info_locales = all("v1/appInfos/#{info['id']}/appInfoLocalizations").to_h { |v| [v["attributes"]["locale"], v] }
    version_locales = all("v1/appStoreVersions/#{VERSION_ID}/appStoreVersionLocalizations").to_h { |v| [v["attributes"]["locale"], v] }
    LOCALES.each do |locale|
      read = ->(field) { File.read(File.join(ROOT, "fastlane/metadata", locale, field + ".txt")).strip }
      app_fields = {name: read.call("name"), subtitle: read.call("subtitle"), privacyPolicyUrl: read.call("privacy_url")}
      fields = {description: read.call("description"), keywords: read.call("keywords"), supportUrl: read.call("support_url")}
      if info_locales[locale]
        patch("appInfoLocalizations", info_locales[locale]["id"], app_fields)
      else
        @api.post("v1/appInfoLocalizations", {data: {type: "appInfoLocalizations", attributes: app_fields.merge(locale: locale),
          relationships: {appInfo: {data: {type: "appInfos", id: info["id"]}}}}})
      end
      # ASC can also create a version localization when App Info is added.
      version_locales = all("v1/appStoreVersions/#{VERSION_ID}/appStoreVersionLocalizations").to_h { |v| [v["attributes"]["locale"], v] }
      if version_locales[locale]
        patch("appStoreVersionLocalizations", version_locales[locale]["id"], fields)
      else
        @client.post_app_store_version_localization(app_store_version_id: VERSION_ID, attributes: fields.merge(locale: locale))
      end
      puts "Metadata written: #{locale}"
    end
    verify_metadata
  end

  def verify_metadata
    info = app_info
    checks = []
    {"appInfos/#{info['id']}/appInfoLocalizations" => {name: "name", subtitle: "subtitle", privacyPolicyUrl: "privacy_url"},
     "appStoreVersions/#{VERSION_ID}/appStoreVersionLocalizations" => {description: "description", keywords: "keywords", supportUrl: "support_url"}}.each do |path, fields|
      localizations = all("v1/#{path}")
      raise "Locale set mismatch" unless localizations.map { |l| l["attributes"]["locale"] }.sort == LOCALES.sort
      localizations.each do |l|
        locale = l["attributes"]["locale"]
        fields.each do |key, file|
          expected = File.read(File.join(ROOT, "fastlane/metadata", locale, file + ".txt")).strip
          raise "Metadata mismatch #{locale}/#{key}" unless l["attributes"][key.to_s].to_s.strip == expected
        end
        checks << {locale: locale, id: l["id"], fields: fields.keys}
      end
    end
    raise "Version mismatch" unless version["attributes"]["versionString"] == "1.0.1"
    save("metadata-verification", {checked_at: Time.now.utc.iso8601, app_id: APP_ID, checks: checks})
  end

  def inspect_commerce
    prices = %w[USA CHN].to_h do |territory|
      points = all("v1/apps/#{APP_ID}/appPricePoints", {filter: {territory: territory}, limit: 200})
      target = territory == "USA" ? "1.99" : "15.0"
      selected = points.select { |p| p["attributes"]["customerPrice"].to_f == target.to_f }
      raise "Ambiguous price point #{territory}" unless selected.length == 1
      [territory, selected.first]
    end
    save("price-points", prices)
    begin
      availability = get("v1/apps/#{APP_ID}/appAvailabilityV2")
    rescue Spaceship::UnexpectedResponse => error
      raise unless error.message.include?("There is no resource of type 'appAvailabilities'")
      availability = {"data" => nil}
    end
    begin
      manual_prices = all("v1/appPriceSchedules/#{APP_ID}/manualPrices", {include: "appPricePoint,territory", limit: 50})
    rescue Spaceship::UnexpectedResponse => error
      raise unless error.message.include?("There is no resource of type 'null' with id '#{APP_ID}'")
      manual_prices = []
    end
    save("commerce-before", {availability: availability,
      territory_availabilities: availability["data"] ? all("v2/appAvailabilities/#{availability['data']['id']}/territoryAvailabilities", {limit: 50, include: "territory"}) : [],
      manual_prices: manual_prices,
      territories: all("v1/territories", {limit: 200})})
    puts "Verified USA $1.99 and CHN CNY 15 current price points"
  end

  def prepare_commerce
    guard!
    inspect_commerce
    current = JSON.parse(File.read(File.join(REPORTS, "commerce-before.json")))
    points = JSON.parse(File.read(File.join(REPORTS, "price-points.json")))
    if current["manual_prices"].empty?
      prices = points.map do |territory, point|
        {type: "appPrices", id: "${price-#{territory}}", attributes: {startDate: nil, endDate: nil},
          relationships: {appPricePoint: {data: {type: "appPricePoints", id: point["id"]}}}}
      end
      body = {data: {type: "appPriceSchedules", relationships: {
        app: {data: {type: "apps", id: APP_ID}}, baseTerritory: {data: {type: "territories", id: "USA"}},
        manualPrices: {data: prices.map { |p| {type: p[:type], id: p[:id]} }}}}, included: prices}
      @api.post("v1/appPriceSchedules", body)
    end
    unless current.dig("availability", "data")
      territories = current["territories"].map do |territory|
        {type: "territoryAvailabilities", id: "${territory-#{territory['id']}}", attributes: {available: true, preOrderEnabled: false},
          relationships: {territory: {data: {type: "territories", id: territory["id"]}}}}
      end
      @api.post("v2/appAvailabilities", {data: {type: "appAvailabilities", attributes: {availableInNewTerritories: true}, relationships: {
        app: {data: {type: "apps", id: APP_ID}}, territoryAvailabilities: {data: territories.map { |t| {type: t[:type], id: t[:id]} }}}}, included: territories})
    end
    verify_commerce
  end

  def verify_commerce
    points = JSON.parse(File.read(File.join(REPORTS, "price-points.json")))
    prices = all("v1/appPriceSchedules/#{APP_ID}/manualPrices", {include: "appPricePoint,territory", limit: 50})
    base = get("v1/appPriceSchedules/#{APP_ID}/baseTerritory")["data"]
    raise "Base territory mismatch" unless base["id"] == "USA"
    points.each do |territory, point|
      price = prices.find { |p| p.dig("relationships", "appPricePoint", "data", "id") == point["id"] }
      raise "Price readback mismatch #{territory}" unless price && price["attributes"]["endDate"].nil?
    end
    availability = get("v1/apps/#{APP_ID}/appAvailabilityV2")["data"]
    raise "Missing availability" unless availability && availability["attributes"]["availableInNewTerritories"] == true
    territories = all("v2/appAvailabilities/#{availability['id']}/territoryAvailabilities", {limit: 50, include: "territory"})
    expected = all("v1/territories", {limit: 200}).map { |t| t["id"] }.sort
    raise "Territory set mismatch" unless territories.map { |t| t.dig("relationships", "territory", "data", "id") }.sort == expected
    raise "Unavailable territory" unless territories.all? { |t| t["attributes"]["available"] == true }
    save("commerce-verification", {checked_at: Time.now.utc.iso8601, base: base, prices: prices, availability: availability, territories: territories})
    puts "Verified prices and #{territories.length} available territories"
  end

  def prepare_ratings
    guard!
    info = app_info
    current = get("v1/appInfos/#{info['id']}/ageRatingDeclaration")["data"]
    ratings = %w[alcoholTobaccoOrDrugUseOrReferences contests gamblingSimulated gunsOrOtherWeapons medicalOrTreatmentInformation profanityOrCrudeHumor sexualContentGraphicAndNudity sexualContentOrNudity horrorOrFearThemes matureOrSuggestiveThemes violenceCartoonOrFantasy violenceRealisticProlongedGraphicOrSadistic violenceRealistic]
    booleans = %w[advertising gambling healthOrWellnessTopics lootBox messagingAndChat parentalControls ageAssurance socialMedia socialMediaAgeRestricted unrestrictedWebAccess userGeneratedContent]
    attributes = ratings.to_h { |k| [k, "NONE"] }.merge(booleans.to_h { |k| [k, false] }).merge("ageRatingOverrideV2" => "NONE", "koreaAgeRatingOverride" => "NONE")
    patch("ageRatingDeclarations", current["id"], attributes)
    patch("apps", APP_ID, {contentRightsDeclaration: "DOES_NOT_USE_THIRD_PARTY_CONTENT"})
    actual = get("v1/appInfos/#{info['id']}/ageRatingDeclaration")["data"]
    raise "Ratings mismatch" unless attributes.all? { |k,v| actual["attributes"][k] == v }
    save("ratings-verification", actual)
  end

  def upload_screenshots
    guard!
    verify_metadata
    require "deliver/upload_screenshots"
    require "deliver/app_screenshot"
    Deliver.cache[:app] = Spaceship::ConnectAPI::App.get(app_id: APP_ID)
    shots = LOCALES.flat_map { |locale| Dir[File.join(ROOT, "fastlane/screenshots", locale, "*.png")].sort.map { |p| Deliver::AppScreenshot.new(p, locale) } }
    raise "Screenshot count mismatch" unless shots.length == 39
    Deliver::UploadScreenshots.new.upload({platform: "osx", overwrite_screenshots: false, skip_screenshots: false, edit_live: false, screenshot_processing_timeout: 1200}, shots)
    verify_screenshots
  end

  def verify_screenshots
    results = []
    localizations = all("v1/appStoreVersions/#{VERSION_ID}/appStoreVersionLocalizations")
    localizations.each do |localization|
      locale = localization["attributes"]["locale"]
      sets = all("v1/appStoreVersionLocalizations/#{localization['id']}/appScreenshotSets")
      raise "Screenshot set mismatch #{locale}" unless sets.length == 1 && sets.first["attributes"]["screenshotDisplayType"] == "APP_DESKTOP"
      shots = all("v1/appScreenshotSets/#{sets.first['id']}/appScreenshots")
      raise "Screenshot count #{locale}" unless shots.length == 3
      shots.each_with_index do |shot, index|
        a = shot["attributes"]
        path = File.join(ROOT, "fastlane/screenshots", locale, "%02d-Mac.png" % (index+1))
        raise "Screenshot incomplete #{locale}" unless a.dig("assetDeliveryState", "state") == "COMPLETE"
        raise "Screenshot order #{locale}" unless a["fileName"] == File.basename(path)
        raise "Screenshot checksum #{locale}" unless a["sourceFileChecksum"] == Digest::MD5.file(path).hexdigest
        raise "Screenshot dimensions #{locale}" unless a.dig("imageAsset", "width") == 2560 && a.dig("imageAsset", "height") == 1600
      end
      results << {locale: locale, screenshots: shots}
    end
    raise "Screenshot locale mismatch" unless results.map { |r| r[:locale] }.sort == LOCALES.sort
    save("screenshots-verification", {checked_at: Time.now.utc.iso8601, sets: results})
  end

  def prepare_privacy
    guard!
    existing = all("v1/apps/#{APP_ID}/dataUsages", {include: "dataProtection"})
    if existing.empty?
      @client.post_app_data_usage(app_id: APP_ID, app_data_usage_protection_id: "DATA_NOT_COLLECTED")
    else
      raise "Unexpected existing privacy declaration" unless existing.length == 1 && existing.first.dig("relationships", "dataProtection", "data", "id") == "DATA_NOT_COLLECTED"
    end
    state = get("v1/apps/#{APP_ID}/dataUsagePublishState")["data"]
    @client.patch_app_data_usages_publish_state(app_data_usages_publish_state_id: state["id"], published: true)
    verify_privacy
  end

  def verify_privacy
    actual = get("v1/apps/#{APP_ID}/dataUsagePublishState")
    raise "Privacy is not published" unless actual.dig("data", "attributes", "published") == true
    usages = get("v1/apps/#{APP_ID}/dataUsages", {include: "dataProtection"})
    raise "Privacy mismatch" unless usages["data"].length == 1 && usages["data"].first.dig("relationships", "dataProtection", "data", "id") == "DATA_NOT_COLLECTED"
    save("privacy-verification", {checked_at: Time.now.utc.iso8601, state: actual, usages: usages})
  end

  def upload_binary
    guard!
    raise "Version mismatch" unless version["attributes"]["versionString"] == "1.0.1"
    builds = Spaceship::ConnectAPI::Build.all(app_id: APP_ID, version: "1.0.1", build_number: "1", platform: "MAC_OS")
    raise "Build exists: inspect processing instead of reuploading" unless builds.empty?
    verification = JSON.parse(File.read(File.join(REPORTS, "pkg-verification.json")))
    pkg = File.join(REPORTS, "export/Pic2Link.pkg")
    raise "Package changed" unless Digest::SHA256.file(pkg).hexdigest == verification["pkg_sha256"]
    validation = File.read(File.join(REPORTS, "apple-validation.log"))
    raise "Apple validation incomplete" unless validation.include?("VERIFY SUCCEEDED with no errors")
    raise "Privacy not verified" unless File.exist?(File.join(REPORTS, "privacy-verification.json"))
    verify_metadata
    verify_screenshots
    verify_commerce
    File.write(File.join(REPORTS, "binary-upload-identity.json"), JSON.pretty_generate({app_id: APP_ID, version: "1.0.1", build: "1", pkg_sha256: verification["pkg_sha256"]}))
    success = system({"API_PRIVATE_KEYS_DIR" => File.dirname(ENV.fetch("ASC_API_PRIVATE_KEY_PATH"))}, "xcrun", "altool", "--upload-package", pkg,
      "--api-key", ENV.fetch("ASC_API_KEY_ID"), "--api-issuer", ENV.fetch("ASC_API_ISSUER_ID"))
    raise "Binary upload failed; inspect ASC before retry" unless success
  end

  def processed_build
    builds = Spaceship::ConnectAPI::Build.all(app_id: APP_ID, version: "1.0.1", build_number: "1", platform: "MAC_OS")
    raise "Expected one processed build" unless builds.length == 1 && builds.first.processing_state == "VALID"
    build = get("v1/builds/#{builds.first.id}")["data"]
    raise "Encryption not confirmed" unless build["attributes"]["usesNonExemptEncryption"] == false
    build
  end

  def select_build
    guard!
    build = processed_build
    current = get("v1/appStoreVersions/#{VERSION_ID}/build")["data"]
    raise "Another build is selected" if current && current["id"] != build["id"]
    @client.patch_app_store_version_with_build(app_store_version_id: VERSION_ID, build_id: build["id"]) unless current
    selected = get("v1/appStoreVersions/#{VERSION_ID}/build")["data"]
    raise "Selected build mismatch" unless selected && selected["id"] == build["id"]
    save("build-verification", {checked_at: Time.now.utc.iso8601, app_id: APP_ID, version_id: VERSION_ID, build: build, selected_build: selected})
  end

  def prepare_review
    guard!
    # Fail closed while the review credentials are blocked. Do not upload the
    # source template as if it were a usable demo configuration.
    notes = File.read(File.join(ROOT, "docs/release/review-notes.txt")).strip
    raise "Review configuration is missing; provision and verify the isolated RAM identity first" if notes.include?("Review configuration must be appended")
    contact = JSON.parse(File.read(ENV.fetch("PIC2LINK_REVIEW_CONTACT_PATH")))
    fields = %w[contactFirstName contactLastName contactEmail contactPhone]
    raise "Incomplete real review contact" unless fields.all? { |k| contact[k].is_a?(String) && !contact[k].strip.empty? }
    raise "International phone required" unless contact["contactPhone"].match?(/\A\+[1-9][0-9\s()-]{6,20}\z/)
    attributes = contact.slice(*fields).merge("notes" => notes, "demoAccountRequired" => false)
    current = get("v1/appStoreVersions/#{VERSION_ID}/appStoreReviewDetail")["data"]
    if current
      patch("appStoreReviewDetails", current["id"], attributes)
    else
      @client.post_app_store_review_detail(app_store_version_id: VERSION_ID, attributes: attributes)
    end
    actual = get("v1/appStoreVersions/#{VERSION_ID}/appStoreReviewDetail")["data"]
    raise "Review details mismatch" unless attributes.all? { |k,v| actual["attributes"][k] == v }
    patch("appStoreVersions", VERSION_ID, {releaseType: "AFTER_APPROVAL"})
    build = processed_build
    @client.patch_app_store_version_with_build(app_store_version_id: VERSION_ID, build_id: build["id"])
    save("review-preparation", {checked_at: Time.now.utc.iso8601, app_id: APP_ID, version_id: VERSION_ID, build_id: build["id"], contact_fields_verified: fields, notes_verified: true})
  end

  def update_reviewer_configuration
    guard!
    before_version = version
    raise "Unexpected version" unless before_version.dig("attributes", "versionString") == "1.0.1"
    raise "Unexpected review state" unless before_version.dig("attributes", "appStoreState") == "REJECTED"
    before_build = get("v1/appStoreVersions/#{VERSION_ID}/build")["data"]
    raise "Unexpected selected build" unless before_build&.dig("attributes", "version") == "1"
    current = get("v1/appStoreVersions/#{VERSION_ID}/appStoreReviewDetail")["data"]
    raise "Missing review details" unless current
    raw = File.read(ENV.fetch("PIC2LINK_REVIEW_CREDENTIAL_PATH"))
    extract = lambda do |label|
      match = raw.match(/#{label}[^A-Za-z0-9]*([A-Za-z0-9]{16,64})/i)
      raise "Invalid credential format" unless match
      match[1]
    end
    key_id = extract.call('AccessKey\\s*ID')
    secret = extract.call('AccessKey\\s*Secret')
    template = File.read(File.join(ROOT, "docs/release/reviewer-configuration.txt"))
    notes = template.gsub("{{ACCESS_KEY_ID}}", key_id).gsub("{{ACCESS_KEY_SECRET}}", secret)
    raise "Invalid notes" if notes.length > 4000 || notes.include?("{{")
    patch("appStoreReviewDetails", current["id"], {notes: notes}) unless current.dig("attributes", "notes") == notes
    actual = get("v1/appStoreVersions/#{VERSION_ID}/appStoreReviewDetail")["data"]
    raise "Notes mismatch" unless actual.dig("attributes", "notes") == notes
    unchanged = current["attributes"].reject { |k,_| k == "notes" }
    raise "Unrelated review fields changed" unless unchanged.all? { |k,v| actual["attributes"][k] == v }
    raise "Version changed" unless version == before_version
    raise "Build changed" unless get("v1/appStoreVersions/#{VERSION_ID}/build")["data"] == before_build
    report = {app_id: APP_ID, version: "1.0.1", selected_build: "1", state: "REJECTED",
      notes_verified: true, unrelated_review_fields_preserved: true, build_and_version_preserved: true}
    File.write(File.join(ROOT, "dist/review-fix-20260911/reviewer-configuration-verification.json"), JSON.pretty_generate(report))
    puts JSON.generate(report)
  end

  def verify_review_readiness
    verify_metadata
    verify_screenshots
    verify_commerce
    build = processed_build
    selected = get("v1/appStoreVersions/#{VERSION_ID}/build")["data"]
    raise "Selected build mismatch" unless selected && selected["id"] == build["id"]
    raise "Release mode mismatch" unless version["attributes"]["releaseType"] == "AFTER_APPROVAL"
    raise "Unexpected phased release" if get("v1/appStoreVersions/#{VERSION_ID}/appStoreVersionPhasedRelease")["data"]
    review = get("v1/appStoreVersions/#{VERSION_ID}/appStoreReviewDetail")["data"]
    raise "Missing review details" unless review && %w[contactFirstName contactLastName contactEmail contactPhone notes].all? { |k| !review["attributes"][k].to_s.empty? }
    info = app_info
    category = get("v1/appInfos/#{info['id']}/primaryCategory")["data"]
    raise "Category mismatch" unless category && category["id"] == "PRODUCTIVITY"
    ratings = get("v1/appInfos/#{info['id']}/ageRatingDeclaration")["data"]
    expected = JSON.parse(File.read(File.join(REPORTS, "ratings-verification.json")))
    raise "Ratings changed" unless ratings["attributes"] == expected["attributes"]
    raise "Content rights mismatch" unless get("v1/apps/#{APP_ID}")["data"]["attributes"]["contentRightsDeclaration"] == "DOES_NOT_USE_THIRD_PARTY_CONTENT"
    # Privacy publishing requires the separately authenticated session lane.
    privacy = JSON.parse(File.read(File.join(REPORTS, "privacy-verification.json")))
    raise "Missing privacy evidence" unless privacy.dig("state", "data", "attributes", "published") == true
    build
  end

  def submit_review
    guard!
    build = verify_review_readiness
    submissions = all("v1/apps/#{APP_ID}/reviewSubmissions", {filter: {platform: "MAC_OS"}})
    active = submissions.reject { |s| s["attributes"]["state"] == "COMPLETE" }
    raise "Multiple active submissions" if active.length > 1
    submission = active.first
    if submission
      raise "Already submitted: verify current state" unless submission["attributes"]["state"] == "READY_FOR_REVIEW"
    else
      submission = @client.post_review_submission(app_id: APP_ID, platform: "MAC_OS").body["data"]
    end
    items = all("v1/reviewSubmissions/#{submission['id']}/items", {include: "appStoreVersion"})
    if items.empty?
      @client.post_review_submission_item(review_submission_id: submission["id"], app_store_version_id: VERSION_ID)
    else
      raise "Unexpected review item" unless items.length == 1 && items.first.dig("relationships", "appStoreVersion", "data", "id") == VERSION_ID
    end
    save("review-submission-attempt", {checked_at: Time.now.utc.iso8601, submission_id: submission["id"], version_id: VERSION_ID, build_id: build["id"]})
    @client.patch_review_submission(review_submission_id: submission["id"], attributes: {submitted: true})
    verify_submission
  end

  def verify_submission
    attempt = JSON.parse(File.read(File.join(REPORTS, "review-submission-attempt.json")))
    submission = get("v1/reviewSubmissions/#{attempt['submission_id']}")["data"]
    items = all("v1/reviewSubmissions/#{submission['id']}/items", {include: "appStoreVersion"})
    raise "Review not waiting/in review" unless %w[WAITING_FOR_REVIEW IN_REVIEW].include?(submission["attributes"]["state"])
    raise "Unexpected review item" unless items.length == 1 && items.first.dig("relationships", "appStoreVersion", "data", "id") == VERSION_ID
    build = verify_review_readiness
    save("submission-verification", {checked_at: Time.now.utc.iso8601, app_id: APP_ID, version: version, build: build, submission: submission, items: items})
  end
end
