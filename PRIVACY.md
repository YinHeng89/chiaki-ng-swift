# chiaki-ng Privacy Policy

Effective 2 November 2026.

chiaki-ng is an independent, unofficial, open-source Remote Play client for PlayStation consoles. It is not affiliated with or endorsed by Sony Interactive Entertainment. This policy covers the chiaki-ng app on macOS and iOS, including the version distributed through the App Store and TestFlight.

## The short version

chiaki-ng's developers do not collect, receive or store any of your data. The app has no accounts of its own, no analytics, no advertising, no tracking and no third-party data collection. What the app keeps stays on your device. What it sends goes only to PlayStation's servers, your own consoles and the people you choose to play or talk with.

## What the app keeps on your device

- **Your PlayStation account sign-in.** When you sign in, the app keeps the account name, account ID and the sign-in tokens PlayStation Network gives it, so you stay signed in.
- **Your consoles.** Console names, network addresses and the pairing keys made when you register a console.
- **Your settings**, such as video, audio and controller settings.
- **Logs** of what the app did, used to diagnose problems. You can hide identifiers in the logs in the Developer settings.
- **Screenshots and clips** from cloud games, only when you choose to save them, in the folder or Photos library you pick.

This data is kept in the app's own storage on your device. The account and console data is held in a database encrypted with a key kept in your device's Keychain.

## What the app sends, and to whom

- **PlayStation Network (Sony).** Your sign-in tokens and the requests needed for the features you use: finding and waking your consoles, remote play, cloud streaming, your game library, trophies, friends, messages, notifications and parties. These go directly from your device to Sony's servers and are handled under [Sony's privacy policy](https://www.playstation.com/legal/privacy-policy/).
- **Your consoles.** Your controller input, and your microphone audio when you use voice chat, are sent to the PlayStation console you are streaming from. The console's video and audio are sent back to your device.
- **People you message.** Messages you send go through PlayStation Network to the friends you send them to.

None of this passes through servers run by chiaki-ng's developers. The app does not sell or share your data with anyone else.

## Permissions the app asks for

- **Microphone:** for voice chat through the console you are streaming from. Used only while the microphone is on in a stream.
- **Local network:** to find and stream from consoles on your network.
- **Bluetooth and USB devices:** for game controllers, including DualSense haptics and adaptive triggers.
- **Photos:** only to add the cloud screenshots and clips you choose to save.
- **Notifications:** to show PlayStation messages, invitations and other alerts from the app.

## Sharing logs and error reports

Logs never leave your device on their own. If you choose to copy or save an error report and send it to someone, for example when reporting a bug on GitHub, you decide what to share. Error reports hide identifiers such as console addresses and account IDs when identifier hiding is on.

## Keeping and deleting your data

Your data stays on your device until you remove it. To remove an account, use **Delete account from this device** in the app's account settings. To remove everything:

- **iPhone and iPad:** delete the app. This removes everything it stored.
- **Mac, App Store version:** delete the app, then delete the folder `~/Library/Containers/io.github.chiaki-ng.chiaki-ng.appstore`.
- **Mac, downloaded version:** delete the app, then delete the folders named `io.github.chiaki-ng.chiaki-ng` in `~/Library/Application Support`, `~/Library/Logs` and `~/Library/Caches`.
- **Either Mac version:** the database key stays in your login Keychain until you delete it in Keychain Access. Its name ends in `.credentials`.

You can also revoke the app's access to your PlayStation account by changing your PlayStation Network password or signing out of all devices in your Sony account settings.

## Children

chiaki-ng is not directed at children and does not knowingly collect any data from anyone, including children.

## Changes

If this policy changes, the new version will be published here with a new effective date. The history of this file is kept in the project's source repository.

## Contact

Questions about this policy can be asked through the project's GitHub issues at https://github.com/chiaki-ng/chiaki-ng-swift/issues or by email to streetpea@proton.me.
