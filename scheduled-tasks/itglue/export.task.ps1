# itglue/export - daily full IT Glue dataset snapshot -> itglue_export_* + relationship edges.
# Cadence: Daily (scheduled-tasks/README.md). One cmdlet call: Invoke-ImperionITGlueExport
# pages every export entity, upserts each into its itglue_export_<entity> table
# (change-detected) and rewrites the polymorphic itglue_export_relationship edges
# (delete-then-insert; re-runs converge). For ad-hoc/backfill slices of a single entity, the
# reusable writer is Invoke-ImperionITGlueExportToBronze (rows -> itglue_export_<entity>).
# Register with Register-ImperionTask (run elevated, under the gMSA/service identity):
#
#   Register-ImperionTask -Name 'Imperion itglue export' `
#     -Command 'Import-Module ImperionPipeline; Initialize-ImperionContext; & "<repo>\scheduled-tasks\itglue\export.task.ps1"' `
#     -Interval Daily

Import-Module ImperionPipeline
Initialize-ImperionContext

Invoke-ImperionITGlueExport
