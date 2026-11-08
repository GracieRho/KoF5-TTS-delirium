# Favilium clinical voice workspace

This branch implements one caregiver recording and researcher-entered Korean text synthesis. Start follow-up work from the latest clinical/voice-only. Do not merge clinical changes into main or replace the original Favilium deployment without explicit user instructions.

- Keep documentation and product copy in Korean. Use the original caregiver workspace and assets described in DESIGN.md.
- Keep researcher access and provider credentials server-side. Do not commit credentials, audio, transcripts, patient identifiers or database files.
- Distinguish verified provider success, verification required, pending or unknown status, and deletion. Keep explicit consent next to voice enrollment. Do not autoplay synthesized voices.
- Describe changes to participant-facing behavior and obtain applicable clinical review before patient use.
- See docs/repository-layout.md and README.md for the layout and environment. Run the backend and frontend checks listed in README.md. Regenerate architecture files when source, configuration or scripts change and verify the generated output.
