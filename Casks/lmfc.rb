cask "lmfc" do
  version "1.0.0"
  sha256 "6d812692bc1a9a1cb0c38cefbee11b032627c17f476d1c4c19fa0764336547a0"

  url "https://github.com/DevnisG/LMFC/releases/download/v#{version}/LMFC-#{version}-macos-arm64.dmg"
  name "LMFC!"
  desc "Block MacBook input and black out displays for cleaning"
  homepage "https://github.com/DevnisG/LMFC"

  depends_on arch: :arm64
  depends_on macos: :sequoia

  app "LMFC.app"

  uninstall quit: "com.devnisg.lmfc"

  zap trash: "~/Library/Preferences/com.devnisg.lmfc.plist"

  caveats do
    unsigned_accessibility
    <<~EOS
      LMFC uses an ad hoc signature and is not notarized by Apple.
      If macOS blocks the first launch, review the warning in
      System Settings > Privacy & Security before choosing Open Anyway.
    EOS
  end
end
