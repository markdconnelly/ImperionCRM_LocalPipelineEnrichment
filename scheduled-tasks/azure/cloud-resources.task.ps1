# azure/cloud-resources - daily per-client Azure ARM cloud-resource inventory -> bronze
# (cloud_subscriptions + cloud_resource_groups + cloud_resources; epic #201 / ADR-0023).
#
# Superseded by the cmdlet-first registration (CLAUDE.md §4): the real scheduled task is
# 'Imperion-CloudResources' -> Invoke-ImperionCloudResourceSync, registered by
# Register-ImperionTask under the service identity. The sync cmdlet discovers the WHOLE
# estate from the account_tenant registry (Settings -> Tenant mapping) and fans out per
# tenant with the enterprise app's cert OR secret (#234, frontend ADR-0103) — no env-var
# tenant list. This thin task file remains for ad-hoc / manual runs and mirrors the cmdlet.

Import-Module ImperionPipeline
Initialize-ImperionContext
Invoke-ImperionCloudResourceSync
