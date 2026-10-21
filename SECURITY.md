# Security policy

## Reporting a vulnerability

Open a private security advisory through GitHub:
<https://github.com/ss-pratapIIITB/Drome/security/advisories/new>

Please do not open a public issue for a vulnerability that could put users at risk. Include the affected version, reproduction steps, and the impact you believe it has.

## Scope

Drome is a browser, so the highest-value areas are:

- JavaScript bridge message handling between the page and native code
- Navigation and URL handling, including custom schemes
- File download handling
- Model checkpoint loading and the Hugging Face download path
- Anything that could cause page content to leave the device

## Model artifacts

The Laya checkpoint is downloaded at runtime from Hugging Face. This repository does not pin a cryptographic hash of the checkpoint beyond the Hugging Face revision behavior. If you depend on this project in a security-sensitive context, vendor and verify the weights yourself.

## Supported versions

Only the latest release on `main` is supported.
