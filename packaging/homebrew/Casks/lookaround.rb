cask "lookaround" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_OF_LookAround-0.1.0.dmg"

  url "https://github.com/henryle97/look-around/releases/download/v#{version}/LookAround-#{version}.dmg"
  name "LookAround"
  desc "Gentle menu-bar break reminders for healthy eyes"
  homepage "https://henryle97.github.io/look-around/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura
  depends_on arch: :arm64

  app "LookAround.app"

  uninstall quit: "com.lookaround.app"

  zap trash: "~/Library/Preferences/com.lookaround.app.plist"
end
