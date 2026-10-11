# features/research — agentic search & attachments

`research_pipeline.dart` — Plan ⇒ Search ⇒ Read ⇒ Synthesize. The model only
writes a JSON query plan; all calls/fetches happen in code. Answers are
scrubbed: `[n]` citations beyond the retrieved sources and any model-written
URL are removed before rendering.

`attachment_bar.dart` — ≤4 images, ≤1280px/80% JPEG re-encode (metadata
stripped), × badges, Hero preview. Shared by Ask + evidence sheet.

`research_trace_view.dart` — collapsible "Researched Ns" tree with live
timer, query rows (provider tags), source rows (favicon, breadcrumb, status
chip), source detail sheet (Open/Copy/Share).
