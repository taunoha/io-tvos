# Io

Io is an independent Apple TV app for watching ERR Jupiter. It offers live ETV, ETV2 and ETV+, on-demand programmes, Lasteekraan, search and local viewing history.

## Install on your Apple TV

You’ll need a Mac with Xcode and a compatible tvOS SDK, an Apple TV running tvOS 27.0 or later, and your own Apple Account. Playback requires an internet connection.

1. Clone the repository or download and extract it using **Code → Download ZIP** on GitHub. Open `Io.xcodeproj` in Xcode.
2. In **Xcode → Settings → Accounts**, add your Apple Account. Select the **Io** target and open **Signing & Capabilities**. Enable **Automatically manage signing**, choose your own **Team** (your **Personal Team** works), and replace `ee.personal.jupiterclient` with a unique bundle identifier, such as `com.yourname.io`.
3. Connect the Mac and Apple TV to the same local network. On Apple TV, open **Settings → Remotes and Devices → Remote App and Devices**. In Xcode’s run destination menu, choose **Manage Devices…**, select your Apple TV in Device Hub and enter the pairing code shown on the TV. [Apple’s pairing guide](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac)
4. In Xcode, select the **Io** scheme and your Apple TV as the run destination, then press **⌘R**. Xcode builds, signs, installs and opens Io.

To update Io or renew an expired development installation, run it again from Xcode with the same Team and bundle identifier. Leave the existing installation in place to preserve viewing history.
