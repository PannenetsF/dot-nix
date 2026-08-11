# Release commit: 3121c4ba5862a49d834a2df301739ac95c08cc4a
# Hide-corner patch: 0141b97956c997decd6692d9602b7e49cf1fc939
cask "aerospace-patched" do
  version "0.21.3-Beta-pf.1"
  sha256 "125ea00f5ece3ce55d14fd5b584fa2f5f1717a460894b526fd0c0a611a11dac1"

  url "https://github.com/PannenetsF/AeroSpace/releases/download/v#{version}/AeroSpace-v#{version}.zip",
      verified: "github.com/PannenetsF/AeroSpace/"
  name "AeroSpace (pf patched)"
  desc "AeroSpace with the pf multi-monitor hide-corner patch"
  homepage "https://github.com/PannenetsF/AeroSpace"

  conflicts_with cask: ["aerospace", "aerospace-dev"]
  depends_on macos: :ventura

  postflight do
    system "xattr -d com.apple.quarantine #{staged_path}/AeroSpace-v#{version}/bin/aerospace"
    system "xattr -d com.apple.quarantine #{appdir}/AeroSpace.app"
  end

  app "AeroSpace-v#{version}/AeroSpace.app"
  binary "AeroSpace-v#{version}/bin/aerospace"

  binary "AeroSpace-v#{version}/shell-completion/zsh/_aerospace",
      target: "#{HOMEBREW_PREFIX}/share/zsh/site-functions/_aerospace"
  binary "AeroSpace-v#{version}/shell-completion/bash/aerospace",
      target: "#{HOMEBREW_PREFIX}/etc/bash_completion.d/aerospace"
  binary "AeroSpace-v#{version}/shell-completion/fish/aerospace.fish",
      target: "#{HOMEBREW_PREFIX}/share/fish/vendor_completions.d/aerospace.fish"

  Dir["#{staged_path}/AeroSpace-v#{version}/manpage/*"].each { |man| manpage man }
end
