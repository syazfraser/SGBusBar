# The Homebrew cask for SGBusBar. It lives in the syazfraser/homebrew-tap repo as Casks/sgbusbar.rb;
# this copy is the template. The release workflow updates version and sha256 there automatically.
cask "sgbusbar" do
  version "0.2.0"
  sha256 "REPLACE_WITH_THE_SHA256_FROM_THE_RELEASE"

  url "https://github.com/syazfraser/SGBusBar/releases/download/v#{version}/SGBusBar-#{version}.zip"
  name "SGBusBar"
  desc "Singapore bus arrival times in the menu bar"
  homepage "https://github.com/syazfraser/SGBusBar"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "SGBusBar.app"

  zap trash: [
    "~/Library/Application Support/SGBusBar",
    "~/Library/Preferences/com.syazwanrifdi.SGBusBar.plist",
  ]

  caveats <<~EOS
    SGBusBar isn't notarised by Apple yet. The first time you open it, macOS may block it:
    open System Settings > Privacy & Security and click "Open Anyway".

    You'll also need a free LTA DataMall API key:
      https://datamall.lta.gov.sg/content/datamall/en/request-for-api.html
  EOS
end
