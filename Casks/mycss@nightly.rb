# MycSs as it is on the `main` branch, rebuilt on every push by
# .github/workflows/nightly.yml. For whoever wants the newest changes.
#
#   brew tap frenkiieeee/mycss https://github.com/frenkiieeee/MycSs
#   brew install --cask frenkiieeee/mycss/mycss@nightly
#   brew upgrade --cask --greedy-latest frenkiieeee/mycss/mycss@nightly   # to follow main
cask "mycss@nightly" do
  version :latest
  sha256 :no_check

  url "https://github.com/frenkiieeee/MycSs/releases/download/nightly/MycSs-nightly.dmg"
  name "MycSs (nightly)"
  desc "Synced lyrics on the lock screen and a notch for music (main branch)"
  homepage "https://github.com/frenkiieeee/MycSs"

  conflicts_with cask: "frenkiieeee/mycss/mycss"
  depends_on macos: :sequoia

  app "MycSs.app"

  # Not notarized: without this macOS says the app is damaged on the first open.
  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "MycSs.app"],
        base:         :appdir,
        must_succeed: false
  end

  uninstall quit: "com.mycss.lyrics"

  zap trash: [
    "~/Library/Application Support/MycSs",
    "~/Library/Caches/MycSs",
    "~/Library/Logs/MycSs.log",
    "~/Library/Preferences/com.mycss.lyrics.plist",
  ]

  caveats <<~EOS
    This is the development build of the `main` branch, not a numbered release.
    It is not notarized: after an update macOS may ask again for Accessibility and
    Full Disk Access.
  EOS
end
