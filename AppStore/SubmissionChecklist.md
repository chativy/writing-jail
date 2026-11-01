# App Store Submission Checklist

## Prepared

- [x] Public privacy policy and support URLs
- [x] Apache 2.0 license
- [x] English name, subtitle, description, keywords, and release notes
- [x] 2880×1800 macOS screenshots
- [x] App privacy questionnaire answers
- [x] App Review notes covering Accessibility usage
- [x] Sandbox and user-selected file entitlements
- [x] XcodeGen project specification
- [x] App Store export options

## Required Before Upload

- [ ] Confirm the App Store Connect app record and SKU.
- [ ] Create or import an Apple Distribution signing certificate for team
  `Y5E45NE7R9`.
- [ ] Create the Mac App Store provisioning profile for
  `com.chativy.writingjail`.
- [ ] Verify sandbox behavior for custom secondary-display images and persisted
  security-scoped access.
- [ ] Test Accessibility-based Input Blocking in the sandboxed App Store build.
- [ ] Archive, validate, and upload through Xcode or Transporter.
- [ ] Complete age rating, pricing, availability, and export-compliance forms.

## Review Risk

Global keyboard interception through Accessibility and deliberate restriction
of app switching may require additional App Review scrutiny. The optional
Limited Mode, clear user consent, visible timer, and five-second emergency exit
mitigate this risk but do not guarantee approval. Review the current App Store
Review Guidelines before submission.
