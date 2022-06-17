Import-Module "$PSScriptRoot\Sitecore.Cloud.Cmdlets.dll"

# public funcitons
Function Start-SitecoreAzureWFFMPackaging {
    <#
        .SYNOPSIS
        Using this command you can create Sitecore Azure WFFM Module web deploy packages

        .DESCRIPTION
        Creates valid Sitecore Azure WFFM Module web deploy packages for all SKU

        .PARAMETER WffmPath
        Path to the Sitecore's wffm module package zip file

        .PARAMETER ReportingWffmPath
        Path to the Sitecore's wffm reporting module package zip file

        .PARAMETER DestinationFolderPath
        Destination folder path which web deploy packages will be generated into

        .PARAMETER CargoPayloadFolderPath
        Path to the root folder containing cargo payloads (*.sccpl files)

        .PARAMETER ParameterXmlPath
        Path to the root folder containing MS Deploy xml files (parameters.xml)

        .EXAMPLE
        Start-WFFMAzurePackaging -WffmPath "D:\Sitecore\Modules\Web Forms for Marketers 8.2 rev. 161129.zip" -ReportingWffmPath "D:\Sitecore\Modules\Web Forms for Marketers Reporting 8.2 rev. 161129.zip" -DestinationFolderPath "D:\Work\WFFMPackaging\Wdps" -CargoPayloadFolderPath "D:\Project\Source\GitRepos\Cloud.Services.Provisioning.Data\Resources\WFFM 8.2.1\CargoPayloads" -ParameterXmlPath "D:\Project\Source\GitRepos\Cloud.Services.Provisioning.Data\Resources\WFFM 8.2.1\MsDeployXmls"
    #>

    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
		[string]$WffmPath,
        [parameter(Mandatory=$false)]
		[string]$ReportingWffmPath,
        [parameter(Mandatory=$true)]
        [string]$DestinationFolderPath,
        [parameter(Mandatory=$true)]
        [string]$CargoPayloadFolderPath,
        [parameter(Mandatory=$true)]
        [string]$ParameterXmlPath
    )

    try {
        $cdCargoPayloadPath = "$CargoPayloadFolderPath\WFFM.Cloud.RoleSpecific_CD.sccpl"
        $prcCargoPayloadPath = "$CargoPayloadFolderPath\WFFM.Cloud.RoleSpecific_PRC.sccpl"
        $xdbSingleCargoPayloadPath = "$CargoPayloadFolderPath\WFFM.Cloud.Role_Specific_XDBSingle.sccpl"
        $repCargoPayloadPath = ""
        $captchaHandlersEmbedCargoPayloadPath = "$CargoPayloadFolderPath\WFFM.Cloud.Embed.CaptchaHandlers.sccpl"
        $singleEmbedCargoPayloadPath = "$CargoPayloadFolderPath\WFFM.Cloud.Embed.RoleSpecific_Single.sccpl"
        $cdEmbedCargoPayloadPath="$CargoPayloadFolderPath\WFFM.Cloud.Embed.RoleSpecific_CD.sccpl"
        $cmEmbedCargoPayloadPath="$CargoPayloadFolderPath\WFFM.Cloud.Embed.RoleSpecific_CM.sccpl"
        $cdWdpParametersXml = "$ParameterXmlPath\CD\parameters.xml"
        $prcWdpParametersXml = "$ParameterXmlPath\PRC\parameters.xml"
        $singleWdpParametersXml = "$ParameterXmlPath\Single\parameters.xml"
        $xdbSingleWdpParametersXml = "$ParameterXmlPath\XDBSingle\parameters.xml"

        if (!$ReportingWffmPath) {
            $ReportingWffmPath = $WffmPath
            $repCargoPayloadPath = "$CargoPayloadFolderPath\WFFM.Cloud.RoleSpecific_REP.sccpl"
            $singleEmbedCargoPayloadPath = $captchaHandlersEmbedCargoPayloadPath
            $cdEmbedCargoPayloadPath = $captchaHandlersEmbedCargoPayloadPath
            $cmEmbedCargoPayloadPath = $captchaHandlersEmbedCargoPayloadPath
            #XDBSingle
            $xdbSingleDestFolder = "$DestinationFolderPath\XDBSingle"
            CreateXDBSingleWffmWdps $xdbSingleDestFolder $WffmPath $xdbSingleWdpParametersXml $xdbSingleCargoPayloadPath
        }

        #XPSingle
        $xpSingleDestFolder = "$DestinationFolderPath\XPSingle"
        CreateSingleWffmWdps $xpSingleDestFolder  $WffmPath $singleEmbedCargoPayloadPath $singleWdpParametersXml

        #XP
        $xpDestFolder = "$DestinationFolderPath\XP"
        CreateCmWffmWdps $xpDestFolder $WffmPath $cmEmbedCargoPayloadPath
        CreateCdWffmWdps $xpDestFolder $WffmPath $cdCargoPayloadPath $cdEmbedCargoPayloadPath $cdWdpParametersXml
        CreatePrcWffmWdps $xpDestFolder $WffmPath $prcCargoPayloadPath $prcWdpParametersXml
        CreateRepWffmWdps $xpDestFolder $ReportingWffmPath $repCargoPayloadPath

        #XDB
        $xdbDestFolder = "$DestinationFolderPath\XDB"
        CreatePrcWffmWdps $xdbDestFolder $WffmPath $prcCargoPayloadPath $prcWdpParametersXml
        CreateRepWffmWdps $xdbDestFolder $ReportingWffmPath $repCargoPayloadPath
    }
    catch {
        Write-Host $_.Exception.Message
        Break
    }
}

# Export public functions
Export-ModuleMember -Function Start-SitecoreAzureWFFMPackaging

Function CreateCmWffmWdps  {
    param(
        [string]$DestFolder,
        [string]$PackageSource,
        [string]$EmbedCargoPayload
        )

        #Create the Wffm Wdp
        $wdpPath = ConvertTo-SCModuleWebDeployPackage -Path $PackageSource -Destination $DestFolder
        Update-SCWebDeployPackage -Path $wdpPath -EmbedCargoPayloadPath $EmbedCargoPayload

        #Rename the wdps to be CM specific
        Rename-Item $wdpPath ($wdpPath -replace ".scwdp.zip", "_cm.scwdp.zip")
}

Function CreateCdWffmWdps {
    param(
        [string]$DestFolder,
        [string]$PackageSource,
        [string]$CargoPayload,
        [string]$EmbedCargoPayload,
        [string]$WdpParametersXml
        )

        #Create the Wffm Wdp
        $wdpPath = ConvertTo-SCModuleWebDeployPackage -Path $PackageSource -Destination $DestFolder -Exclude "*.sql","*App_Data\poststeps\*"
        Update-SCWebDeployPackage -Path $wdpPath -EmbedCargoPayloadPath $EmbedCargoPayload
        Update-SCWebDeployPackage -Path $wdpPath -CargoPayloadPath $CargoPayload

        #Update the archive/parameters xmls
        Update-SCWebDeployPackage -Path $wdpPath -ParametersXmlPath $WdpParametersXml

        #Rename the wdps to be CD specific
        Rename-Item $wdpPath ($wdpPath -replace ".scwdp.zip", "_cd.scwdp.zip")
}

Function CreatePrcWffmWdps {
    param(
        [string]$DestFolder,
        [string]$PackageSource,
        [string]$CargoPayload,
        [string]$WdpParametersXml
        )

        #Create the Wffm Wdp
        $wdpPath = ConvertTo-SCModuleWebDeployPackage -Path $PackageSource -Destination $DestFolder -Exclude "core.sql","master.sql","*App_Data\poststeps\*"
        Update-SCWebDeployPackage -Path $wdpPath -CargoPayloadPath $CargoPayload

        #Update the archive/parameters xmls
        Update-SCWebDeployPackage -Path $wdpPath -ParametersXmlPath $WdpParametersXml

        #Rename the wdps to be PRC specific
        Rename-Item $wdpPath ($wdpPath -replace ".scwdp.zip", "_prc.scwdp.zip")
}

Function CreateRepWffmWdps {
    param(
        [string]$DestFolder,
        [string]$PackageSource,
        [string]$CargoPayload
        )

        #Create the Wffm Wdp
        $wdpPath = ConvertTo-SCModuleWebDeployPackage -Path $PackageSource -Destination $DestFolder -Exclude "core.sql","master.sql","*App_Data\poststeps\*"

        if ($CargoPayload) {
            Update-SCWebDeployPackage -Path $wdpPath -CargoPayloadPath $CargoPayload
        }

        #Rename the wdps to be REP specific
        Rename-Item $wdpPath ($wdpPath -replace ".scwdp.zip", "_rep.scwdp.zip")
}

Function CreateSingleWffmWdps {
    param(
        [string]$DestFolder,
        [string]$PackageSource,
        [string]$EmbedCargoPayload,
        [string]$ParametersXml
        )

        #Create the Wffm Wdp

        $wdpPath = ConvertTo-SCModuleWebDeployPackage -Path $PackageSource -Destination $DestFolder

        Update-SCWebDeployPackage -Path $wdpPath -EmbedCargoPayloadPath $EmbedCargoPayload

        #Update the archive/parameters xmls
        Update-SCWebDeployPackage -Path $wdpPath -ParametersXmlPath $ParametersXml

        #Rename the wdps to be Single specific
        Rename-Item $wdpPath ($wdpPath -replace ".scwdp.zip", "_single.scwdp.zip")
}

Function CreateXDBSingleWffmWdps {
    param(
        [string]$DestFolder,
        [string]$PackageSource,
        [string]$ParametersXml,
        [string]$CargoPayload
        )

        #Create the Wffm Wdp
        $wdpPath = ConvertTo-SCModuleWebDeployPackage -Path $PackageSource -Destination $DestFolder -Exclude "core.sql","master.sql","*App_Data\poststeps\*"
        Update-SCWebDeployPackage -Path $wdpPath -CargoPayloadPath $CargoPayload

        #Update the archive/parameters xmls
        Update-SCWebDeployPackage -Path $wdpPath -ParametersXmlPath $ParametersXml

        #Rename the wdps to be XDBSingle specific
        Rename-Item $wdpPath ($wdpPath -replace ".scwdp.zip", "_xdbsingle.scwdp.zip")
}
# SIG # Begin signature block
# MIIbVAYJKoZIhvcNAQcCoIIbRTCCG0ECAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUWN9deXQ+LEWhEvCcijLy2Rp1
# 6sGgggpvMIIFMDCCBBigAwIBAgIQBAkYG1/Vu2Z1U0O1b5VQCDANBgkqhkiG9w0B
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
# T8aTEAb8B4H6i9r5gkn3Ym6hU/oSlBiFLpKR6mhsRDKyZqHnGKSaZFHvMIIFNzCC
# BB+gAwIBAgIQD7DIiKzIDvOVbd7QfMY3fjANBgkqhkiG9w0BAQsFADByMQswCQYD
# VQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGln
# aWNlcnQuY29tMTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgQ29k
# ZSBTaWduaW5nIENBMB4XDTIwMDkwMzAwMDAwMFoXDTIxMTEwMTEyMDAwMFowdDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCkNhbGlmb3JuaWExFjAUBgNVBAcTDVNhbiBG
# cmFuY2lzY28xGzAZBgNVBAoTElNpdGVjb3JlIFVTQSwgSW5jLjEbMBkGA1UEAxMS
# U2l0ZWNvcmUgVVNBLCBJbmMuMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKC
# AQEAzVvUn7sL32KesFMdld4mE20SLgZeDQNgd72nw4uPnNfKnSAMSctBSRapyZ8n
# rApWObVxfr5wrRqS93IXP1Hmf5wNxOIzV69mKtDKVLuLGVIVfY54qBFNa95tbyJX
# fZUU38BVgv1vJoV+XMvbCueF2aBACeBiCQ2CBoGujr/L5LlTteOH81UXM23yWJt2
# 5gNIoi5zscnn0IC10jvUcuw6YNcmMZYR8V2BJKdqL2T4NsA16aG+vDk13wdhxqfw
# CwYTWiTR8iIszZl5/ZM2dYn9DJNTPP1RhYEGlwdv6ppjr6fQqWC1NSYi62nc9IzB
# Z7k7zkiZ2ll8MamvrCnwQThFcQIDAQABo4IBxTCCAcEwHwYDVR0jBBgwFoAUWsS5
# eyoKo6XqcQPAYPkt9mV1DlgwHQYDVR0OBBYEFD3QmHkA+pK+PANv4T8P0Xc5tBbY
# MA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzB3BgNVHR8EcDBu
# MDWgM6Axhi9odHRwOi8vY3JsMy5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVkLWNz
# LWcxLmNybDA1oDOgMYYvaHR0cDovL2NybDQuZGlnaWNlcnQuY29tL3NoYTItYXNz
# dXJlZC1jcy1nMS5jcmwwTAYDVR0gBEUwQzA3BglghkgBhv1sAwEwKjAoBggrBgEF
# BQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzAIBgZngQwBBAEwgYQG
# CCsGAQUFBwEBBHgwdjAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQu
# Y29tME4GCCsGAQUFBzAChkJodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGln
# aUNlcnRTSEEyQXNzdXJlZElEQ29kZVNpZ25pbmdDQS5jcnQwDAYDVR0TAQH/BAIw
# ADANBgkqhkiG9w0BAQsFAAOCAQEA8ZhbyfAXwHnmgE3ghKSf8DpKpaPncViCv1j+
# gaiBqOpdGhptU+ag18WFLKui9FRmhjrZ0qp08eNftfoITW53FbBe0o2GgnapsRKg
# tXpm/25/zh4h/AHGMA1A2n4fZNFrVGEIdokCHIuabyaYKEGN/r0iVs8ZZYktQIAW
# F0QE1spdf/AoP4xGcgoZgRgdEc4smMj6OE83kca00HVEoli7mC/eBSo/iUyDZYo0
# ANFST3GCQ/URgpQz0kFJfAjrLdxTC4I+rHm0i8XdtQOpoi8N25CfJR9560q9OnjH
# lAYmmXg0y7W3uEdFvMrg3yfYCJFDisWK2rKEn7YP+Q7ujjWCjjGCEE8wghBLAgEB
# MIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNV
# BAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNz
# dXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEA+wyIisyA7zlW3e0HzGN34wCQYFKw4D
# AhoFAKBwMBAGCisGAQQBgjcCAQwxAjAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3
# AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEW
# BBQRr6oyub5dQlV9w8Vk3kogw5IoFTANBgkqhkiG9w0BAQEFAASCAQBCGRPsV0OX
# P1/CYZYiKJapoxuKjA5Dp2An658Hl6UjwF0frO8++gk+SXa0MfVc5dTPFO7J7711
# Sg2XDQswihp9hBRBWRABz3AljLPf4xmlaxJb9N3pzZ80nkYFn+u1MeVeNFKH8d02
# bhc10krUMsmu9ennjYv9oM+3y7RZ8RmalNEMW0JdxnDJDDvXrrYLUatBkuklBCKX
# i0u03SveEOXV5PK85fbCLBp8n0p2cweTtW8yX69h2ni4cz72Ft4EwUYhkVD8do/q
# 5HNhXQ06KmLLa7uJ9Y6K651f/XC9NNjRXgGNNw+CG6ewom1lzG61cQGepmSG/SM+
# I1jVem32QRGYoYIOKzCCDicGCisGAQQBgjcDAwExgg4XMIIOEwYJKoZIhvcNAQcC
# oIIOBDCCDgACAQMxDTALBglghkgBZQMEAgEwgf4GCyqGSIb3DQEJEAEEoIHuBIHr
# MIHoAgEBBgtghkgBhvhFAQcXAzAhMAkGBSsOAwIaBQAEFFIoqtvhZFuf1wY/BBie
# 9xi/rJxyAhRo405Hao6zLDvukq0/P0OWN4tWGhgPMjAyMTEwMjkxMDMxMDJaMAMC
# AR6ggYakgYMwgYAxCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jw
# b3JhdGlvbjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29yazExMC8GA1UE
# AxMoU3ltYW50ZWMgU0hBMjU2IFRpbWVTdGFtcGluZyBTaWduZXIgLSBHM6CCCosw
# ggU4MIIEIKADAgECAhB7BbHUSWhRRPfJidKcGZ0SMA0GCSqGSIb3DQEBCwUAMIG9
# MQswCQYDVQQGEwJVUzEXMBUGA1UEChMOVmVyaVNpZ24sIEluYy4xHzAdBgNVBAsT
# FlZlcmlTaWduIFRydXN0IE5ldHdvcmsxOjA4BgNVBAsTMShjKSAyMDA4IFZlcmlT
# aWduLCBJbmMuIC0gRm9yIGF1dGhvcml6ZWQgdXNlIG9ubHkxODA2BgNVBAMTL1Zl
# cmlTaWduIFVuaXZlcnNhbCBSb290IENlcnRpZmljYXRpb24gQXV0aG9yaXR5MB4X
# DTE2MDExMjAwMDAwMFoXDTMxMDExMTIzNTk1OVowdzELMAkGA1UEBhMCVVMxHTAb
# BgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMR8wHQYDVQQLExZTeW1hbnRlYyBU
# cnVzdCBOZXR3b3JrMSgwJgYDVQQDEx9TeW1hbnRlYyBTSEEyNTYgVGltZVN0YW1w
# aW5nIENBMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAu1mdWVVPnYxy
# XRqBoutV87ABrTxxrDKPBWuGmicAMpdqTclkFEspu8LZKbku7GOz4c8/C1aQ+GIb
# fuumB+Lef15tQDjUkQbnQXx5HMvLrRu/2JWR8/DubPitljkuf8EnuHg5xYSl7e2v
# h47Ojcdt6tKYtTofHjmdw/SaqPSE4cTRfHHGBim0P+SDDSbDewg+TfkKtzNJ/8o7
# 1PWym0vhiJka9cDpMxTW38eA25Hu/rySV3J39M2ozP4J9ZM3vpWIasXc9LFL1M7o
# CZFftYR5NYp4rBkyjyPBMkEbWQ6pPrHM+dYr77fY5NUdbRE6kvaTyZzjSO67Uw7U
# NpeGeMWhNwIDAQABo4IBdzCCAXMwDgYDVR0PAQH/BAQDAgEGMBIGA1UdEwEB/wQI
# MAYBAf8CAQAwZgYDVR0gBF8wXTBbBgtghkgBhvhFAQcXAzBMMCMGCCsGAQUFBwIB
# FhdodHRwczovL2Quc3ltY2IuY29tL2NwczAlBggrBgEFBQcCAjAZGhdodHRwczov
# L2Quc3ltY2IuY29tL3JwYTAuBggrBgEFBQcBAQQiMCAwHgYIKwYBBQUHMAGGEmh0
# dHA6Ly9zLnN5bWNkLmNvbTA2BgNVHR8ELzAtMCugKaAnhiVodHRwOi8vcy5zeW1j
# Yi5jb20vdW5pdmVyc2FsLXJvb3QuY3JsMBMGA1UdJQQMMAoGCCsGAQUFBwMIMCgG
# A1UdEQQhMB+kHTAbMRkwFwYDVQQDExBUaW1lU3RhbXAtMjA0OC0zMB0GA1UdDgQW
# BBSvY9bKo06FcuCnvEHzKaI4f4B1YjAfBgNVHSMEGDAWgBS2d/ppSEefUxLVwuoH
# MnYH0ZcHGTANBgkqhkiG9w0BAQsFAAOCAQEAdeqwLdU0GVwyRf4O4dRPpnjBb9fq
# 3dxP86HIgYj3p48V5kApreZd9KLZVmSEcTAq3R5hF2YgVgaYGY1dcfL4l7wJ/RyR
# R8ni6I0D+8yQL9YKbE4z7Na0k8hMkGNIOUAhxN3WbomYPLWYl+ipBrcJyY9TV0GQ
# L+EeTU7cyhB4bEJu8LbF+GFcUvVO9muN90p6vvPN/QPX2fYDqA/jU/cKdezGdS6q
# ZoUEmbf4Blfhxg726K/a7JsYH6q54zoAv86KlMsB257HOLsPUqvR45QDYApNoP4n
# bRQy/D+XQOG/mYnb5DkUvdrk08PqK1qzlVhVBH3HmuwjA42FKtL/rqlhgTCCBUsw
# ggQzoAMCAQICEHvU5a+6zAc/oQEjBCJBTRIwDQYJKoZIhvcNAQELBQAwdzELMAkG
# A1UEBhMCVVMxHTAbBgNVBAoTFFN5bWFudGVjIENvcnBvcmF0aW9uMR8wHQYDVQQL
# ExZTeW1hbnRlYyBUcnVzdCBOZXR3b3JrMSgwJgYDVQQDEx9TeW1hbnRlYyBTSEEy
# NTYgVGltZVN0YW1waW5nIENBMB4XDTE3MTIyMzAwMDAwMFoXDTI5MDMyMjIzNTk1
# OVowgYAxCzAJBgNVBAYTAlVTMR0wGwYDVQQKExRTeW1hbnRlYyBDb3Jwb3JhdGlv
# bjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1c3QgTmV0d29yazExMC8GA1UEAxMoU3lt
# YW50ZWMgU0hBMjU2IFRpbWVTdGFtcGluZyBTaWduZXIgLSBHMzCCASIwDQYJKoZI
# hvcNAQEBBQADggEPADCCAQoCggEBAK8Oiqr43L9pe1QXcUcJvY08gfh0FXdnkJz9
# 3k4Cnkt29uU2PmXVJCBtMPndHYPpPydKM05tForkjUCNIqq+pwsb0ge2PLUaJCj4
# G3JRPcgJiCYIOvn6QyN1R3AMs19bjwgdckhXZU2vAjxA9/TdMjiTP+UspvNZI8uA
# 3hNN+RDJqgoYbFVhV9HxAizEtavybCPSnw0PGWythWJp/U6FwYpSMatb2Ml0UuNX
# bCK/VX9vygarP0q3InZl7Ow28paVgSYs/buYqgE4068lQJsJU/ApV4VYXuqFSEEh
# h+XetNMmsntAU1h5jlIxBk2UA0XEzjwD7LcA8joixbRv5e+wipsCAwEAAaOCAccw
# ggHDMAwGA1UdEwEB/wQCMAAwZgYDVR0gBF8wXTBbBgtghkgBhvhFAQcXAzBMMCMG
# CCsGAQUFBwIBFhdodHRwczovL2Quc3ltY2IuY29tL2NwczAlBggrBgEFBQcCAjAZ
# GhdodHRwczovL2Quc3ltY2IuY29tL3JwYTBABgNVHR8EOTA3MDWgM6Axhi9odHRw
# Oi8vdHMtY3JsLndzLnN5bWFudGVjLmNvbS9zaGEyNTYtdHNzLWNhLmNybDAWBgNV
# HSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMCB4AwdwYIKwYBBQUHAQEE
# azBpMCoGCCsGAQUFBzABhh5odHRwOi8vdHMtb2NzcC53cy5zeW1hbnRlYy5jb20w
# OwYIKwYBBQUHMAKGL2h0dHA6Ly90cy1haWEud3Muc3ltYW50ZWMuY29tL3NoYTI1
# Ni10c3MtY2EuY2VyMCgGA1UdEQQhMB+kHTAbMRkwFwYDVQQDExBUaW1lU3RhbXAt
# MjA0OC02MB0GA1UdDgQWBBSlEwGpn4XMG24WHl87Map5NgB7HTAfBgNVHSMEGDAW
# gBSvY9bKo06FcuCnvEHzKaI4f4B1YjANBgkqhkiG9w0BAQsFAAOCAQEARp6v8Lii
# X6KZSM+oJ0shzbK5pnJwYy/jVSl7OUZO535lBliLvFeKkg0I2BC6NiT6Cnv7O9Ni
# v0qUFeaC24pUbf8o/mfPcT/mMwnZolkQ9B5K/mXM3tRr41IpdQBKK6XMy5voqU33
# tBdZkkHDtz+G5vbAf0Q8RlwXWuOkO9VpJtUhfeGAZ35irLdOLhWa5Zwjr1sR6nGp
# QfkNeTipoQ3PtLHaPpp6xyLFdM3fRwmGxPyRJbIblumFCOjd6nRgbmClVnoNyERY
# 3Ob5SBSe5b/eAL13sZgUchQk38cRLB8AP8NLFMZnHMweBqOQX1xUiz7jM1uCD8W3
# hgJOcZ/pZkU/djGCAlowggJWAgEBMIGLMHcxCzAJBgNVBAYTAlVTMR0wGwYDVQQK
# ExRTeW1hbnRlYyBDb3Jwb3JhdGlvbjEfMB0GA1UECxMWU3ltYW50ZWMgVHJ1c3Qg
# TmV0d29yazEoMCYGA1UEAxMfU3ltYW50ZWMgU0hBMjU2IFRpbWVTdGFtcGluZyBD
# QQIQe9Tlr7rMBz+hASMEIkFNEjALBglghkgBZQMEAgGggaQwGgYJKoZIhvcNAQkD
# MQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEPFw0yMTEwMjkxMDMxMDJaMC8G
# CSqGSIb3DQEJBDEiBCAIZE6Gz/5rQZf12pshsBAa4kNDvDcVTPYRiNk9iE0LejA3
# BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDEdM52AH0COU4NpeTefBTGgPniggE8/vZT
# 7123H99h+DALBgkqhkiG9w0BAQEEggEAJAOHCHJAMO7RNb9Oyerai0P39E9PLQl3
# aTk4ewTrLGu+q0ktus1awxAcvXBc70rbRQYVwqclUqDgpFqoC29itsAa3nFcQqbo
# Zvfl/in4HcXMp6vn+fdlOfGMN7ieB7pL6INkL6XErScyUnq4S6KC6hOKzjgaywRE
# 0v7j6Y7riC+yrQos+FuEfQzdjxcBklWJLyuY9hoM0+MfhmOnd7n9NNI8UKHGm1RF
# HGacHiixgkd6ypBJF6vNEJd8hOIe9TiKm2NFc2tUHBUF/+y3h7ae/zsTgJOVHIS7
# zkeuljc4AdkwNkwD60x3dlrZK0NRbw8SYJjDE+riqakIewb0/QiHfw==
# SIG # End signature block
