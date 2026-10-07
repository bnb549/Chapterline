# App Review notes

Paste this paragraph into App Store Connect → App Review Information → Notes:

No account. Offline DRM-free player. On the empty library, tap Add sample, or import the attached public-domain M4B with the Import button, or open it from Files. Audible .aa/.aax are rejected on purpose. Playback continues on the Lock Screen. Listening stats stay on device.

Attach the same bundled file in App Store Connect → App Review Information (the file attachment on that screen). This repo cannot upload it there.

- Bundled file: `Chapterline/Resources/Sample/TheRaven.m4b`
- Source page: https://librivox.org/the-raven-by-edgar-allan-poe/
- Source file: https://archive.org/download/raven/the_raven_librivox.m4b
- Work: Edgar Allan Poe, “The Raven”, read by Chris Goringe for LibriVox and dedicated to the public domain
- The bundled M4B is that recording. Title and author tags were set with `ffmpeg -c copy` (no re-encode) so import shows title “The Raven” and author “Edgar Allan Poe”. Duration is 9 minutes 31 seconds. The file is about 4.5 MB.
