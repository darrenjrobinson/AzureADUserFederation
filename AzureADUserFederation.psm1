
function Get-AzureADUserGuestTenants {
    <#
    .SYNOPSIS
        Lookup an Azure Active Directory Member User Account and return Tenants where there's a related B2B Guest User Account.

    .DESCRIPTION
        Lookup an Azure Active Directory Member User Account and return Tenants where there's a related B2B Guest User Account.
        
    .EXAMPLE
        Get-AzureADUserGuestTenants -userUPN 'user@domain.com'

    .EXAMPLE
        Get-AzureADUserGuestTenants -userUPN 'user@domain.com' -forceAuth $true

    .EXAMPLE
        'user@domain.com' | Get-AzureADUserGuestTenants  
    #>

    [CmdletBinding()]
    param(
        # User to look up for Tenants it is federated to as a B2B Guest
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$userUPN,
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [boolean]$forceAuth = $false
    )

    # MSAL.PS required for AzureAD Authentication
    if (-not(Get-Module -ListAvailable -Name MSAL.PS)) { Install-Module -Name MSAL.PS -Force -AllowClobber -scope CurrentUser }

    # AzureADTenantID required to validate Tenant
    if (-not(Get-Module -ListAvailable -Name AzureADTenantID)) { Install-Module -Name AzureADTenantID -Force -AllowClobber -scope CurrentUser }

    # Load PS Modules
    if (-not(get-module MSAL.PS)) { Import-Module MSAL.PS }
    if (-not(get-module AzureADTenantId)) { Import-Module AzureADTenantId }

    $Global:myAccessToken = $null 
    # Use the Azure PowerShell Well-Known Client ID
    $clientID = "1950a258-227b-4e31-a9cf-717495945fc2"
    $scopes = "https://management.azure.com/user_impersonation"

    $tenantName = $userUPN.Split("@")[1]
    $tenantID = $null 
    $tenantID = Get-AzureADTenantId -domain $tenantName  
    if (!$tenantID) {
        break 
    }

    try {
        if (!$forceAuth) {
            # Check the MSAL Cache for the UPN being looked up
            $clientApplication = Get-MsalClientApplication -ClientId $clientID -Authority "https://login.microsoftonline.com/$($tenantID)/" -ErrorAction SilentlyContinue
            $msalCacheObj = $null 
            $msalCacheObj = $clientApplication | Get-MsalAccount -Username $userUPN -ErrorAction SilentlyContinue

            if ($msalCacheObj) {
                if ($msalCacheObj.Username -eq $userUPN) {
                    # Get new token using MSAL Cache for the user being looked up                
                    #Write-Host -ForegroundColor blue "Refreshing tokens for '$($userUPN)' using the MSAL Cached Refresh Token."
                    $Global:myAccessToken = Get-MsalToken -ClientId $clientID -silent -TenantId $tenantId -Scopes $scopes -LoginHint $userUPN -RedirectUri "http://localhost" -Authority "https://login.microsoftonline.com/$($tenantID)/" -ForceRefresh
                }
            }
            else {
                # No MSAL Cache for this ClientID and User. Need to login for tokens
                #write-host -ForegroundColor Blue "'$($userUPN)' not found in MSAL Cache for ClientID '$($clientID)'."
                $Global:myAccessToken = Get-MsalToken -Interactive -ClientId $clientID -TenantId $tenantID -LoginHint $userUPN -Scopes $scopes -RedirectUri "http://localhost" -Authority "https://login.microsoftonline.com/$($tenantID)/"
            }
        }
        else {
            # Force Auth as requested by -forceAuth
            #write-host -ForegroundColor Blue "'$($userUPN)' Force re-authentication triggered."
            $Global:myAccessToken = Get-MsalToken -Interactive -ClientId $clientID -TenantId $tenantID -LoginHint $userUPN -Scopes $scopes -RedirectUri "http://localhost" -Authority "https://login.microsoftonline.com/$($tenantID)/"
        }
    }
    catch {
        # Write-Host -ForegroundColor Yellow "No MSAL trickery failed"
        $Global:myAccessToken = Get-MsalToken -Interactive -ClientId $clientID -TenantId $tenantID -LoginHint $userUPN -Scopes $scopes -RedirectUri "http://localhost" -Authority "https://login.microsoftonline.com/$($tenantID)/"
    }

    if ($myAccessToken.AccessToken) {
        $myFederatedTenants = $null 
        $myFederatedTenants = (Invoke-RestMethod -Headers @{Authorization = "Bearer $($myAccessToken.AccessToken)" } `
                -Uri "https://management.azure.com/tenants?api-version=2020-01-01 " `
                -Method Get).value

        $federationTemplate = [pscustomobject][ordered]@{ 
            defaultDomain           = $null 
            customRegisteredDomains = $null  
        } 

        $outputResult = @()
        foreach ($fedTenant in $myFederatedTenants) {
            $fedDetails = $federationTemplate.PsObject.Copy()
            $fedDetails.defaultDomain = $fedTenant.defaultDomain
            $fedDetails.customRegisteredDomains = $fedTenant.domains
            $outputResult += $fedDetails
        }
        return $outputResult
    }
    else {
        return "Authentication Failed for '$($userUPN)'"
    }
} 

Export-ModuleMember -Function 'Get-AzureADUserGuestTenants'

# SIG # Begin signature block
# MIINSwYJKoZIhvcNAQcCoIINPDCCDTgCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU5nLXeB4QBvgTCCOYdzpqDNEx
# 6xegggqNMIIFMDCCBBigAwIBAgIQBAkYG1/Vu2Z1U0O1b5VQCDANBgkqhkiG9w0B
# AQsFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVk
# IElEIFJvb3QgQ0EwHhcNMTMxMDIyMTIwMDAwWhcNMjgxMDIyMTIwMDAwWjByMQsw
# CQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cu
# ZGlnaWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQg
# Q29kZSBTaWduaW5nIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
# +NOzHH8OEa9ndwfTCzFJGc/Q+0WZsTrbRPV/5aid2zLXcep2nQUut4/6kkPApfmJ
# 1DcZ17aq8JyGpdglrA55KDp+6dFn08b7KSfH03sjlOSRI5aQd4L5oYQjZhJUM1B0
# sSgmuyRpwsJS8hRniolF1C2ho+mILCCVrhxKhwjfDPXiTWAYvqrEsq5wMWYzcT6s
# cKKrzn/pfMuSoeU7MRzP6vIK5Fe7SrXpdOYr/mzLfnQ5Ng2Q7+S1TqSp6moKq4Tz
# rGdOtcT3jNEgJSPrCGQ+UpbB8g8S9MWOD8Gi6CxR93O8vYWxYoNzQYIH5DiLanMg
# 0A9kczyen6Yzqf0Z3yWT0QIDAQABo4IBzTCCAckwEgYDVR0TAQH/BAgwBgEB/wIB
# ADAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0lBAwwCgYIKwYBBQUHAwMweQYIKwYBBQUH
# AQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYI
# KwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFz
# c3VyZWRJRFJvb3RDQS5jcnQwgYEGA1UdHwR6MHgwOqA4oDaGNGh0dHA6Ly9jcmw0
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwOqA4oDaG
# NGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RD
# QS5jcmwwTwYDVR0gBEgwRjA4BgpghkgBhv1sAAIEMCowKAYIKwYBBQUHAgEWHGh0
# dHBzOi8vd3d3LmRpZ2ljZXJ0LmNvbS9DUFMwCgYIYIZIAYb9bAMwHQYDVR0OBBYE
# FFrEuXsqCqOl6nEDwGD5LfZldQ5YMB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6en
# IZ3zbcgPMA0GCSqGSIb3DQEBCwUAA4IBAQA+7A1aJLPzItEVyCx8JSl2qB1dHC06
# GsTvMGHXfgtg/cM9D8Svi/3vKt8gVTew4fbRknUPUbRupY5a4l4kgU4QpO4/cY5j
# DhNLrddfRHnzNhQGivecRk5c/5CxGwcOkRX7uq+1UcKNJK4kxscnKqEpKBo6cSgC
# PC6Ro8AlEeKcFEehemhor5unXCBc2XGxDI+7qPjFEmifz0DLQESlE/DmZAwlCEIy
# sjaKJAL+L3J+HNdJRZboWR3p+nRka7LrZkPas7CM1ekN3fYBIM6ZMWM9CBoYs4Gb
# T8aTEAb8B4H6i9r5gkn3Ym6hU/oSlBiFLpKR6mhsRDKyZqHnGKSaZFHvMIIFVTCC
# BD2gAwIBAgIQDOzRdXezgbkTF+1Qo8ZgrzANBgkqhkiG9w0BAQsFADByMQswCQYD
# VQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGln
# aWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgQ29k
# ZSBTaWduaW5nIENBMB4XDTIwMDYxNDAwMDAwMFoXDTIzMDYxOTEyMDAwMFowgZEx
# CzAJBgNVBAYTAkFVMRgwFgYDVQQIEw9OZXcgU291dGggV2FsZXMxFDASBgNVBAcT
# C0NoZXJyeWJyb29rMRowGAYDVQQKExFEYXJyZW4gSiBSb2JpbnNvbjEaMBgGA1UE
# CxMRRGFycmVuIEogUm9iaW5zb24xGjAYBgNVBAMTEURhcnJlbiBKIFJvYmluc29u
# MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwj7PLmjkknFA0MIbRPwc
# T1JwU/xUZ6UFMy6AUyltGEigMVGxFEXoVybjQXwI9hhpzDh2gdxL3W8V5dTXyzqN
# 8LUXa6NODjIzh+egJf/fkXOgzWOPD5fToL7mm4JWofuaAwv2DmI2UtgvQGwRhkUx
# Y3hh0+MNDSyz28cqExf8H6mTTcuafgu/Nt4A0ddjr1hYBHU4g51ZJ96YcRsvMZSu
# 8qycBUNEp8/EZJxBUmqCp7mKi72jojkhu+6ujOPi2xgG8IWE6GqlmuMVhRSUvF7F
# 9PreiwPtGim92RG9Rsn8kg1tkxX/1dUYbjOIgXOmE1FAo/QU6nKVioJMNpNsVEBz
# /QIDAQABo4IBxTCCAcEwHwYDVR0jBBgwFoAUWsS5eyoKo6XqcQPAYPkt9mV1Dlgw
# HQYDVR0OBBYEFOh6QLkkiXXHi1nqeGozeiSEHADoMA4GA1UdDwEB/wQEAwIHgDAT
# BgNVHSUEDDAKBggrBgEFBQcDAzB3BgNVHR8EcDBuMDWgM6Axhi9odHRwOi8vY3Js
# My5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVkLWNzLWcxLmNybDA1oDOgMYYvaHR0
# cDovL2NybDQuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJlZC1jcy1nMS5jcmwwTAYD
# VR0gBEUwQzA3BglghkgBhv1sAwEwKjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cu
# ZGlnaWNlcnQuY29tL0NQUzAIBgZngQwBBAEwgYQGCCsGAQUFBwEBBHgwdjAkBggr
# BgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tME4GCCsGAQUFBzAChkJo
# dHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRTSEEyQXNzdXJlZElE
# Q29kZVNpZ25pbmdDQS5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOC
# AQEANWoHDjN7Hg9QrOaZx0V8MK4c4nkYBeFDCYAyP/SqwYeAtKPA7F72mvmJV6E3
# YZnilv8b+YvZpFTZrw98GtwCnuQjcIj3OZMfepQuwV1n3S6GO3o30xpKGu6h0d4L
# rJkIbmVvi3RZr7U8ruHqnI4TgbYaCWKdwfLb/CUffaUsRX7BOguFRnYShwJmZAzI
# mgBx2r2vWcZePlKH/k7kupUAWSY8PF8O+lvdwzVPSVDW+PoTqfI4q9au/0U77UN0
# Fq/ohMyQ/CUX731xeC6Rb5TjlmDhdthFP3Iho1FX0GIu55Py5x84qW+Ou+OytQcA
# FZx22DA8dAUbS3P7OIPamcU68TGCAigwggIkAgEBMIGGMHIxCzAJBgNVBAYTAlVT
# MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
# b20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25p
# bmcgQ0ECEAzs0XV3s4G5ExftUKPGYK8wCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcC
# AQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYB
# BAGCNwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFH3lGJrwpUA3
# GnrsRDDR7bvZvgt/MA0GCSqGSIb3DQEBAQUABIIBAHXd55yt5OX/WHawcZLditgA
# 2b9qxxUct4zy6ZL5vIRMQ71PaBzW6v1sztz29txvxdsOE0/Mz7ENdIp2Rd2DKvuB
# fYVeYNwQQS1i0l5n/CbYU/AmJ/mQ4KlW14VKgpUDVO0pQgqZN6QYVYFBUim1vuUD
# dY3p76SNy51aldvTtYRt4McfUO7OkkzwPQZL8qiCw0fFU2Ba0zQQT57nNOrKXCTF
# kEnNzB6otjUCCpeALHeuDfAZ1Ankc5HJMla5DHEGtiZ+79gDSlP8t63VlfM/2nyl
# a32KPoF1pjoDv/Gd83MQk2zngNjNDFaiztv3NoVS9SGDKOVEX8im90nyLvs0Doc=
# SIG # End signature block
