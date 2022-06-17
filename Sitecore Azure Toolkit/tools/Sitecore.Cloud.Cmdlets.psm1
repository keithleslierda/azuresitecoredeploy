if (Test-Path "$PSScriptRoot\Sitecore.Cloud.Cmdlets.dll") {
  Import-Module "$PSScriptRoot\Sitecore.Cloud.Cmdlets.dll"
}
elseif (Test-Path "$PSScriptRoot\bin\Sitecore.Cloud.Cmdlets.dll") {
  Import-Module "$PSScriptRoot\bin\Sitecore.Cloud.Cmdlets.dll"
}
else {
  throw "Failed to find Sitecore.Cloud.Cmdlets.dll, searched $PSScriptRoot and $PSScriptRoot\bin"
}

# public functions
Function Start-SitecoreAzureDeployment{
    <#
        .SYNOPSIS
        You can deploy a new Sitecore instance on Azure for a specific SKU

        .DESCRIPTION
        Deploys a new instance of Sitecore on Azure

        .PARAMETER location
        Standard Azure region (e.g.: North Europe)
        .PARAMETER Name
        Name of the deployment
        .PARAMETER ArmTemplateUrl
        Url to the ARM template
        .PARAMETER ArmTemplatePath
        Path to the ARM template
        .PARAMETER ArmParametersPath
        Path to the ARM template parameter
        .PARAMETER LicenseXmlPath
        Path to a valid Sitecore license
        .PARAMETER SetKeyValue
        This is a hash table, use to set the unique values for the deployment parameters in Arm Template Parameters Json

        .EXAMPLE
        Import-Module -Verbose .\Cloud.Services.Provisioning.SDK\tools\Sitecore.Cloud.Cmdlets.psm1
        $SetKeyValue = @{
        "deploymentId"="xP0-QA";
        "Sitecore.admin.password"="!qaz2wsx";
        "sqlserver.login"="xpsqladmin";
        "sqlserver.password"="Password12345";    "analytics.mongodb.connectionstring"="mongodb://17.54.72.145:27017/xP0-QA-analytics";
        "tracking.live.mongodb.connectionstring"="mongodb://17.54.72.145:27017/xP0-QA-tracking_live";
        "tracking.history.mongodb.connectionstring"="mongodb://17.54.72.145:27017/xP0-QA-tracking_history";
        "tracking.contact.mongodb.connectionstring"="mongodb://17.54.72.145:27017/xP0-QA-tracking_contact"
        }
        Start-SitecoreAzureDeployment -Name $SetKeyValue.deploymentId -Region "North Europe" -ArmTemplatePath "C:\dev\azure\xP0.Template.json" -ArmParametersPath "xP0.Template.params.json" -LicenseXmlPath "D:\xp0\license.xml" -SetKeyValue $SetKeyValue
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [alias("Region")]
        [string]$Location,
        [parameter(Mandatory=$true)]
        [string]$Name,
        [parameter(ParameterSetName="Template URI", Mandatory=$true)]
        [string]$ArmTemplateUrl,
        [parameter(ParameterSetName="Template Path", Mandatory=$true)]
        [string]$ArmTemplatePath,
        [parameter(Mandatory=$true)]
        [string]$ArmParametersPath,
        [parameter(Mandatory=$true)]
        [string]$LicenseXmlPath,
        [hashtable]$SetKeyValue
    )

    try {
        Write-Host "Deployment Started..."

        if ([string]::IsNullOrEmpty($ArmTemplateUrl) -and [string]::IsNullOrEmpty($ArmTemplatePath)) {
            Write-Host "Either ArmTemplateUrl or ArmTemplatePath is required!"
            Break
        }

        if(!($Name -cmatch '^(?!.*--)[a-z0-9]{2}(|([a-z0-9\-]{0,37})[a-z0-9])$'))
        {
            Write-Error "Name should only contain lowercase letters, digits or dashes,
                         dash cannot be used in the first two or final character,
                         it cannot contain consecutive dashes and is limited between 2 and 40 characters in length!"
            Break;
        }

        if ($SetKeyValue -eq $null) {
            $SetKeyValue = @{}
        }

        # Set the Parameters in Arm Template Parameters Json
        $paramJson = Get-Content $ArmParametersPath -Raw

        Write-Verbose "Setting ARM template parameters..."
        
        # Read and Set the license.xml
        $licenseXml = Get-Content $LicenseXmlPath -Raw -Encoding UTF8
        $SetKeyValue.Add("licenseXml", $licenseXml)

        # Update params and save to a temporary file
        $paramJsonFile = "temp_$([System.IO.Path]::GetRandomFileName())"
        Set-SCAzureDeployParameters -ParametersJson $paramJson -SetKeyValue $SetKeyValue | Set-Content $paramJsonFile -Encoding UTF8

        Write-Verbose "ARM template parameters are set!"

        # Deploy Sitecore in given Location
        Write-Verbose "Deploying Sitecore Instance..."
        $notPresent = Get-AzResourceGroup -Name $Name -ev notPresent -ea 0
        if (!$notPresent) {
            New-AzResourceGroup -Name $Name -Location $Location -Tag @{ "provider" = "b51535c2-ab3e-4a68-95f8-e2e3c9a19299" }
        }
        else {
            Write-Verbose "Resource Group Already Exists."
        }

        if ([string]::IsNullOrEmpty($ArmTemplateUrl)) {
            $PSResGrpDeployment = New-AzResourceGroupDeployment -Name $Name -ResourceGroupName $Name -TemplateFile $ArmTemplatePath -TemplateParameterFile $paramJsonFile
        }else{
            # Replace space character in the url, as it's not being replaced by the cmdlet itself
            $PSResGrpDeployment = New-AzResourceGroupDeployment -Name $Name -ResourceGroupName $Name -TemplateUri ($ArmTemplateUrl -replace ' ', '%20') -TemplateParameterFile $paramJsonFile
        }
        $PSResGrpDeployment
    }
    catch {
        Write-Error $_.Exception.Message
        Break
    }
    finally {
      if ($paramJsonFile) {
        Remove-Item $paramJsonFile
      }
    }
}

Function Start-SitecoreAzurePackaging{
    <#
        .SYNOPSIS
        Using this command you can create SKU specific Sitecore Azure web deploy packages

        .DESCRIPTION
        Creates valid Azure web deploy packages for SKU specified in the sku configuration file

        .PARAMETER sitecorePath
        Path to the Sitecore's zip file
        .PARAMETER destinationFolderPath
        Destination folder path which web deploy packages will be generated into
        .PARAMETER cargoPayloadFolderPath
        Path to the root folder containing cargo payloads (*.sccpl files)
        .PARAMETER commonConfigPath
        Path to the common.packaging.config.json file
        .PARAMETER skuConfigPath
        Path to the sku specific config file (e.g.: xp1.packaging.config.json)
        .PARAMETER parameterXmlPath
        Path to the root folder containing MS Deploy xml files (parameters.xml)
        .PARAMETER fileVersion
        Generates a text file called version.txt, containing value passed to this parameter and puts it in the webdeploy package for traceability purposes - this parameter is optional
        .PARAMETER integratedSecurity
        Indicates should integrated security be used in connectionString. False by default

        .EXAMPLE
        Start-SitecoreAzurePackaging -sitecorePath "C:\Sitecore\Sitecore 8.2 rev. 161103.zip" ` -destinationPath .\xp1 `
        -cargoPayloadFolderPath .\Cloud.Services.Provisioning.SDK\tools\CargoPayloads `
        -commonConfigPath .\Cloud.Services.Provisioning.SDK\tools\Configs\common.packaging.config.json `
        -skuConfigPath .\Cloud.Services.Provisioning.SDK\tools\Configs\xp1.packaging.config.json `
        -parameterXmlPath .\Cloud.Services.Provisioning.SDK\tools\MSDeployXmls
        -integratedSecurity $true
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [string]$SitecorePath,
        [parameter(Mandatory=$true)]
        [string]$DestinationFolderPath,
        [parameter(Mandatory=$true)]
        [string]$CargoPayloadFolderPath,
        [parameter(Mandatory=$true)]
        [string]$CommonConfigPath,
        [parameter(Mandatory=$true)]
        [string]$SkuConfigPath,
        [parameter(Mandatory=$true)]
        [string]$ParameterXmlPath,
        [parameter(Mandatory=$false)]
        [string]$FileVersion,
        [parameter(Mandatory=$false)]
        [bool]$IntegratedSecurity
    )

    try {

        $DestinationFolderPath = AddTailBackSlashToPathIfNotExists($DestinationFolderPath)
        $cargoPayloadFolderPath = AddTailBackSlashToPathIfNotExists($CargoPayloadFolderPath)
        $ParameterXmlPath = AddTailBackSlashToPathIfNotExists($ParameterXmlPath)

        # Create the Raw Web Deploy Package
        Write-Verbose "Creating the Raw Web Deploy Package..."
        if ($FileVersion -eq $null) {
                $sitecoreWebDeployPackagePath = New-SCWebDeployPackage -Path $SitecorePath -Destination $DestinationFolderPath -IntegratedSecurity $IntegratedSecurity
        }
        else {
                $sitecoreWebDeployPackagePath = New-SCWebDeployPackage -Path $SitecorePath -Destination $DestinationFolderPath -FileVersion $FileVersion -IntegratedSecurity $IntegratedSecurity -Force
        }
        Write-Verbose "Raw Web Deploy Package Created Successfully!"

        # Read and Apply the common Configs
        $commonConfigs = (Get-Content $CommonConfigPath -Raw) | ConvertFrom-Json
        $commonSccplPaths = @()
        foreach($sccpl in $commonConfigs.sccpls)
        {
            $commonSccplPaths += $CargoPayloadFolderPath + $sccpl;
        }

        Write-Verbose "Applying Common Cloud Configurations..."
        Update-SCWebDeployPackage -Path $sitecoreWebDeployPackagePath -CargoPayloadPath $commonSccplPaths
        Write-Verbose "Common Cloud Configurations Applied Successfully!"

        # Read the SKU Configs
        $skuconfigs = (Get-Content $SkuConfigPath -Raw) | ConvertFrom-Json
        foreach($scwdp in $skuconfigs.scwdps)
        {
            # Create the role specific scwdps
            $roleScwdpPath =  $sitecoreWebDeployPackagePath -replace ".scwdp", ("_" + $scwdp.role + ".scwdp")
            Copy-Item $sitecoreWebDeployPackagePath $roleScwdpPath -Verbose

            # Apply the role specific cargopayloads
            $sccplPaths = @()
            foreach($sccpl in $scwdp.sccpls)
            {
                $sccplPaths += $CargoPayloadFolderPath + $sccpl;
            }
            if ($sccplPaths.Length -gt 0) {
                Write-Verbose "Applying $($scwdp.role) Role Specific Configurations..."
                Update-SCWebDeployPackage -Path $roleScwdpPath -CargoPayloadPath $sccplPaths
                Write-Verbose "$($scwdp.role) Role Specific Configurations Applied Successfully!"
            }

            # Set the role specific parameters.xml and archive.xml
            Write-Verbose "Setting $($scwdp.role) Role Specific Web Deploy Package Parameters XML and Generating Archive XML..."
            Update-SCWebDeployPackage -Path $roleScwdpPath -ParametersXmlPath ($ParameterXmlPath + $scwdp.parametersXml)
            Write-Verbose "$($scwdp.role) Role Specific Web Deploy Package Parameters and Archive XML Added Successfully!"
        }

        # Remove the Raw Web Deploy Package
        Remove-Item -Path $sitecoreWebDeployPackagePath
    }
    catch {
        Write-Host $_.Exception.Message
        Break
    }
}

Function Start-SitecoreAzureModulePackaging {
    <#
        .SYNOPSIS
        Using this command you can create Sitecore Azure Module web deploy packages

        .DESCRIPTION
        Creates valid Sitecore Azure Module web deploy packages

        .PARAMETER SourceFolderPath
        Source folder path to the Sitecore's exm module package zip files

        .PARAMETER DestinationFolderPath
        Destination folder path which web deploy packages will be generated into

        .PARAMETER CargoPayloadFolderPath
        Root folder path which contain cargo payloads (*.sccpl files)

		.PARAMETER AdditionalWdpContentsFolderPath
        Root folder path which contain folders with additional contents to Wdp

        .PARAMETER ParameterXmlPath
        Root folder path which contain the msdeploy xml files (parameters.xml)

        .PARAMETER ConfigFilePath
        File path of SKU and Role config json files

        .EXAMPLE
		Start-SitecoreAzureModulePackaging -SourceFolderPath "D:\Sitecore\Modules\Email Experience Manager 3.5.0 rev. 170310" -DestinationFolderPath "D:\Work\EXM\WDPs" -CargoPayloadFolderPath "D:\Resources\EXM 3.5\CargoPayloads" -AdditionalWdpContentsFolderPath "D:\Work\EXM\AdditionalFiles" -ParameterXmlFolderPath "D:\Resources\EXM 3.5\MsDeployXmls" -ConfigFile "D:\Resources\EXM 3.5\Configs\EXM0.Packaging.config.json"
    #>

    [CmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        [string]$SourceFolderPath,
        [parameter(Mandatory=$true)]
        [string]$DestinationFolderPath,
        [parameter(Mandatory=$true)]
        [string]$CargoPayloadFolderPath,
		[parameter(Mandatory=$true)]
        [string]$AdditionalWdpContentsFolderPath,
        [parameter(Mandatory=$true)]
        [string]$ParameterXmlFolderPath,
        [parameter(Mandatory=$true)]
        [string]$ConfigFilePath
    )

    # Read the role config
    $skuconfigs = (Get-Content $ConfigFilePath -Raw) | ConvertFrom-Json
    ForEach($scwdp in $skuconfigs.scwdps) {

        # Find source package path
        Get-ChildItem $SourceFolderPath | Where-Object { $_.Name -match $scwdp.sourcePackagePattern } |
        Foreach-Object {
            $packagePath = $_.FullName
        }

        # Create the Wdp
        $wdpPath = ConvertTo-SCModuleWebDeployPackage -Path $packagePath -Destination $DestinationFolderPath

        # Apply the Cargo Payloads
        ForEach($sccpl in $scwdp.sccpls) {
            $cargoPayloadPath = $sccpl
            Update-SCWebDeployPackage -Path $wdpPath -CargoPayloadPath "$CargoPayloadFolderPath\$cargoPayloadPath"
        }

        # Embed the Cargo Payloads
        ForEach($embedSccpl in $scwdp.embedSccpls) {
            $embedCargoPayloadPath = $embedSccpl
            Update-SCWebDeployPackage -Path $wdpPath -EmbedCargoPayloadPath "$CargoPayloadFolderPath\$embedCargoPayloadPath"
        }

		# Add additional Contents To Wdp from given Folders
		ForEach($additionalContentFolder in $scwdp.additionalWdpContentsFolders) {
			$additionalContentsFolderPath = $additionalContentFolder
			Update-SCWebDeployPackage -Path $wdpPath -SourcePath "$AdditionalWdpContentsFolderPath\$additionalContentsFolderPath"
		}

		# Update the ParametersXml
		if($scwdp.parametersXml) {
			$parametersXml = $scwdp.parametersXml
			Update-SCWebDeployPackage -Path $wdpPath -ParametersXmlPath "$ParameterXmlFolderPath\$parametersXml"
		}

        # Rename the Wdp to be more role specific
        $role = $scwdp.role
        Rename-Item $wdpPath ($wdpPath -replace ".scwdp.zip", "_$role.scwdp.zip")
    }
}

Function ConvertTo-SitecoreWebDeployPackage {
    <#
        .SYNOPSIS
        Using this command, you can convert a Sitecore package to a web deploy package

        .DESCRIPTION
        Creates a new webdeploypackage from the Sitecore package passed to it

        .PARAMETER Path
        Path to the Sitecore installer package
        .PARAMETER Destination
        Destination folder that web deploy package will be created into - optional parameter, if not passed will use the current location
        .PARAMETER Force
        If set, will overwrite existing web deploy package with the same name

        .EXAMPLE
        ConvertTo-SitecoreWebDeployPackage -Path "C:\Sitecore\Modules\Web Forms for Marketers 8.2 rev. 160801.zip" -Force

        .REMARKS
        Currently, this CmdLet creates a webdeploy package only from "files" folder of the package
    #>
    [Obsolete("Use Start-SitecoreAzureModulePackaging for Sitecore module packaging")]
    [CmdletBinding()]
    param(
    [parameter(Mandatory=$true)]
    [string]$Path,
    [parameter()]
    [string]$Destination,
    [parameter()]
    [switch]$Force
    )

    if(!$Destination -or $Destination -eq "") {
        $Destination = (Get-Location).Path
    }

    if($Force) {
        return ConvertTo-SCWebDeployPackage -PSPath $Path -Destination $Destination -Force
    } else {
        return ConvertTo-SCWebDeployPackage -PSPath $Path -Destination $Destination
    }
}

Function Set-SitecoreAzureTemplates {
    <#
        .SYNOPSIS
        Using this command you can upload Sitecore ARM templates to an Azure Storage

        .DESCRIPTION
        Uploads all the ARM Templates files in the given folder and the sub folders to given Azure Storage in the same folder hierarchy

        .PARAMETER Path
        Path to the Sitecore ARM Templates folder
        .PARAMETER StorageContainerName
        Name of the target container in the Azure Storage Account
        .PARAMETER AzureStorageContext
        Azure Storage Context object returned by New-AzureStorageContext
        .PARAMETER StorageConnectionString
        Connection string of the target Azure Storage Account
        .PARAMETER Force
        If set, will overwrite existing templates with the same name in the target container

        .EXAMPLE
        $StorageContext = New-AzStorageContext -StorageAccountName "samplestorageaccount" -StorageAccountKey "3pQEA23emk0aio2RK6luL0MfP2P81lg9JEo4gHSEHkejL9+/9HCU4IjhsgAbcXnQz6j72B3Xq8TZZpwj4GI+Qw=="
        Set-SitecoreAzureTemplates -Path "D:\Work\UploadSitecoreTemplates\Templates" -StorageContainerName "samplecontainer" -AzureStorageContext $StorageContext
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [string]$Path,
        [parameter(Mandatory=$true)]
        [string]$StorageContainerName,
        [parameter(ParameterSetName="context",Mandatory=$true)]
        [System.Object]$AzureStorageContext,
        [parameter(ParameterSetName="connstring",Mandatory=$true)]
        [string]$StorageConnectionString,
        [parameter()]
        [switch]$Force
    )

    if ([string]::IsNullOrEmpty($StorageConnectionString) -and ($AzureStorageContext -eq $null)) {
        Write-Host "Either StorageConnectionString or AzureStorageContext is required!"
        Break
    }

    if ($StorageConnectionString) {
        $AzureStorageContext = New-AzStorageContext -ConnectionString $StorageConnectionString
    }

    $absolutePath = Resolve-Path -Path $Path
    $absolutePath = AddTailBackSlashToPathIfNotExists($absolutePath)

    $urlList = @()
    $files = Get-ChildItem $Path -Recurse -Filter "*.json"

    foreach($file in $files)
    {
        $localFile = $file.FullName
        $blobFile = $file.FullName.Replace($absolutePath, "")

        if ($Force) {
            $blobInfo = Set-AzStorageBlobContent -File $localFile -Container $StorageContainerName -Blob $blobFile -Context $AzureStorageContext -Force
        } else{
            $blobInfo = Set-AzStorageBlobContent -File $localFile -Container $StorageContainerName -Blob $blobFile -Context $AzureStorageContext
        }

        $urlList += $blobInfo.ICloudBlob.uri.AbsoluteUri
    }

    return ,$urlList
}

# Export public functions
Export-ModuleMember -Function Start-SitecoreAzureDeployment
Export-ModuleMember -Function Start-SitecoreAzurePackaging
Export-ModuleMember -Function Start-SitecoreAzureModulePackaging
Export-ModuleMember -Function ConvertTo-SitecoreWebDeployPackage
Export-ModuleMember -Function Set-SitecoreAzureTemplates
Export-ModuleMember -Cmdlet New-SCCargoPayload

# Internal functions
Function AddTailBackSlashToPathIfNotExists {
 param( [string]$Path)

    $Path = $Path.Trim()
    if (!$Path.EndsWith("\"))
    {
        $Path = $Path + "\"
    }

    return $Path
}

# SIG # Begin signature block
# MIIbVAYJKoZIhvcNAQcCoIIbRTCCG0ECAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU4qiDBF1BmKmplnTVwUmP6W75
# T92gggpvMIIFMDCCBBigAwIBAgIQBAkYG1/Vu2Z1U0O1b5VQCDANBgkqhkiG9w0B
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
# BBRiVyGEhhkf1d4BxBgW5QUo+d2CQjANBgkqhkiG9w0BAQEFAASCAQA4C5V0sqlu
# BhRfqFUx3eYHh0HVGnOoY1zYu+On7x+kp9mNlSJqeFC5jdUygq7bN113fXiK2UdK
# l6b4u7yYHQktrIhFg0qqAGF6qgOnpuCmvGRN0mOFb3oDxKpCpnzuqAGUSQ1m8i4G
# vwApp8PWhWVm2hiuRKFrR2wk3V/E07IO7Arx0JKQd62Lh9aLAXyn4NIizrxITdYx
# scZOhNoD9sTlOHalhbjUF5Gg2/t2fAagEO55ccabdNbuyr08nyjTsvlModvS77A4
# zCudR1bKpmnLqv3E3qmTowKcjobgJrfjnLmK2NZ/QW1aHN8pID7YgRBeDchdvJ1Y
# YZArJlix2kqioYIOKzCCDicGCisGAQQBgjcDAwExgg4XMIIOEwYJKoZIhvcNAQcC
# oIIOBDCCDgACAQMxDTALBglghkgBZQMEAgEwgf4GCyqGSIb3DQEJEAEEoIHuBIHr
# MIHoAgEBBgtghkgBhvhFAQcXAzAhMAkGBSsOAwIaBQAEFBs824npHWbzRn17WM/G
# KxmozOLGAhRaVFIYDNnCdGOoOU4c5OpYp+htJBgPMjAyMTEwMjkxMDMxMDFaMAMC
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
# MQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEPFw0yMTEwMjkxMDMxMDFaMC8G
# CSqGSIb3DQEJBDEiBCDPQ9mKZM7B/tisf8YpDoyP+ZsIwhoWYXeam54uw3kKmzA3
# BgsqhkiG9w0BCRACLzEoMCYwJDAiBCDEdM52AH0COU4NpeTefBTGgPniggE8/vZT
# 7123H99h+DALBgkqhkiG9w0BAQEEggEAmByLEcv1YEjpRmKtSpEN9UYo24mPW2OW
# qxPE0YKTYVa9OwsemoCSNK7jaOWLSTfWQA51VnQ2s2r/RAr1REfgR/Fjlx9O01S6
# L7/si3R1G7CYFB1pzexyvngwYW+DKhJMbZAEyJU7MLg6gmqAcQsEoNrhxepd9h2z
# SmUx/hzcWUmi6ulfHLoAmgKOCqAK2zF+XvGrd65oYuud2nLHmOxw/v75xLe7oz9u
# ad1VERXVnrUEN0oJvpcX1ykyupKSsVjei4sMLH89PGXJAJDEWKqyFPqBu65tw+9c
# PRCXazKVYczcv58ROSB2BVtyVPxaIBXLtiATJbg8n2COcwZr5+ldrg==
# SIG # End signature block
