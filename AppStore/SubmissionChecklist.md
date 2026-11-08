# App Store Submission Checklist

## Prepared

- [x] Public privacy policy and support URLs
- [x] Apache 2.0 license
- [x] English name, subtitle, description, keywords, and release notes
- [x] Five 2880×1800 macOS screenshots, including full-screen focus mode
- [x] App Review notes covering Accessibility usage
- [x] Sandbox and user-selected file entitlements
- [x] Privacy manifest and export-compliance declaration
- [x] XcodeGen project specification
- [x] App Store export options
- [x] App Store record, bundle ID, SKU, category, and age rating
- [x] US$10 one-time price
- [x] Availability in all 175 App Store territories
- [x] Mac App Store distribution certificate and provisioning profile
- [x] Universal archive validated and uploaded (build 12)
- [x] Build 12 attached to version 1.0
- [x] App privacy questionnaire answers documented

## Manual Completion

- [x] Publish App Privacy answers with no data collection.
- [ ] Confirm the Paid Applications Agreement, tax, and banking information are
  active for the organization.
- [ ] Install the signed build on a Mac, grant Accessibility access, and verify
  Cmd-Tab and Mission Control remain blocked during a focus session. On macOS
  27 and later, macOS requires adding the app manually with `+`.
- [x] Submit version 1.0 with build 12 and all five screenshots for App Review.
  The resubmission entered `WAITING_FOR_REVIEW` on November 8, 2026.

## Review Risk

Global keyboard interception through Accessibility and deliberate restriction
of app switching may require additional App Review scrutiny. The optional
Limited Mode, clear user consent, visible timer, and five-second emergency exit
mitigate this risk but do not guarantee approval. Review the current App Store
Review Guidelines before submission.
