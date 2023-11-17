# Copyright 2019 Dynatrace LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script automates the Dynatrace OneAgent installation for Azure WebApps
#
# Before using this script, you need to install the Azure PowerShell: https://azure.microsoft.com/en-us/documentation/articles/powershell-install-configure/
# After that, open a PowerShell window and type 'Add-AzureAccount'. Enter your azure user-credentials in the prompt that pops up.
# If you have multiple subscriptions make sure you select the subscription which contains your app. 
# To list your subscriptions type 'Get-AzureRmSubscription'. To select a subscription type 'Select-AzureSubscription'.
#
# usage:
# .\dynatrace-azure-updater.ps1 <websitename> <deployment-username> <deployment-password> <environment> <API token>
#
# <websitename> the name of your Azure WebApp
# <deployment-username>/<deployment-password> Your azure deployment credentials, which you can set in the azure portal under "App Deployment" > "Deployment credentials"
# <environment>/<API token> Your Dynatrace environment ID and token, which you can find in Dynatrace under "Deploy Dynatrace"

param (
	[Parameter(Mandatory=$true)][string]$websitename,
	[Parameter(Mandatory=$true)][string]$username,
	[string]$password = $( Read-Host "Input password, please" ),
	[Parameter(Mandatory=$true)][string]$tenant,
	[Parameter(Mandatory=$true)][string]$tenanttoken
)

# ==================================================
# function section
# ==================================================

function Log($level, $content) {	
	$line = "{0} {1} {2}" -f (Get-Date), $level, $content
	Write-Output ("LOG: {0}" -f $line)
}

function LogInfo($content) {	
	Log "INFO" $content
}

function LogWarning($content) {	
	Log "WARNING" $content
}

function LogError($content) {	
	if ($_.Exception -ne $null) {
		Log "ERROR" ("Exception.Message = {0}" -f $_.Exception.Message)
	}
	Log "ERROR" $content
}

function ExitFailed() {
	Log "ABORT" "Installation failed. See log.txt for more information."
	Exit 
}

function ExitSuccess() {
	Exit
}

# ==================================================
# main script
# ==================================================

LogInfo "getting site-info for '$websitename'..."

# update appsettings
try {
	$website = Get-AzureWebsite $websitename

	LogInfo "updating settings for '$websitename'..."
	$website.AppSettings['DT_TENANT'] = $tenant
	$website.AppSettings['DT_API_TOKEN'] = $tenanttoken
	$website.AppSettings['WEBSITE_PRIVATE_EXTENSIONS'] = '0' # disable all extensions to recover from potentially corrupted installations
	Set-AzureWebsite $websitename -AppSettings $website.AppSettings
} catch {		
	$ErrorMessage = $_.Exception.Message
	LogError "error accessing website via Azure PowerShell: $ErrorMessage"
	ExitFailed
}


	$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username,$password)))

	$apiBaseUrl = "https://$websitename.scm.azurewebsites.net/api"

try {
	# uninstall extension ruxitAgent
	LogInfo "Uninstalling ruxitAgent extension for '$websitename'..."
	Invoke-RestMethod -Uri "$apiBaseUrl/siteextensions/ruxitAgent" -Method DELETE -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
	LogInfo "Uninstalled ruxitAgent extension for '$websitename'"
} catch {		
	$ErrorMessage = $_.Exception.Message
	LogInfo "Unable to uninstall ruxitAgent extension. Probably it's not installed, so you can safely ignore this message."
}

try {
	LogInfo "Uninstalling Dynatrace extension for '$websitename'..."
	Invoke-RestMethod -Uri "$apiBaseUrl/siteextensions/Dynatrace" -Method DELETE -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}
	LogInfo "Uninstalled Dynatrace extension for '$websitename'"
} catch {		
	$ErrorMessage = $_.Exception.Message
	LogInfo "Unable to uninstall Dynatrace extension. Probably it's not installed, so you can safely ignore this message."
}

try {
	# install extension
	LogInfo "installing extension for '$websitename'..."
	Invoke-RestMethod -Uri "$apiBaseUrl/siteextensions/Dynatrace" -Method PUT -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}

	# get log file
	LogInfo "SiteExtensions/Dynatrace/log.txt"
	LogInfo "================================="
	Invoke-RestMethod -Uri "$apiBaseUrl/vfs/SiteExtensions/Dynatrace/log.txt" -Method GET -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)}

	$website.AppSettings['WEBSITE_PRIVATE_EXTENSIONS'] = '1' # re-enable extensions
	Set-AzureWebsite $websitename -AppSettings $website.AppSettings
} catch {		
	$ErrorMessage = $_.Exception.Message
	LogError "error accessing website via Azure PowerShell: $ErrorMessage"
	ExitFailed
}

LogInfo "finished"
ExitSuccess
