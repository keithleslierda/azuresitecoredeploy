$SCSDK="C:\projects\GMAC\Azure\Sitecore Azure Toolkit"
$SCTemplates="https://github.com/keithleslierda/azuresitecoredeploy/raw/main/"
$DeploymentId = "rg-east-us2-dev-sitecore"
$LicenseFile = "license.xml"
$SubscriptionId = "08691e42-d4cb-4017-887c-c1dc27e73c53"
$Location="EastUS2"
$ParamFile="azuredeploy.parameters.json"

$Parameters = @{

     #set the size of all recommended instance sizes  

     "sitecoreSKU"="Single";

     #by default this installs azuresearch

     #if you uncomment the following it will use an existing solr connectionstring that

     # you have created instead of using AzureSearch                                                                                                                                                             

     "solrConnectionString"= "http://aze-dsolr01:8983/solr";

}

Import-Module $SCSDK\tools\Sitecore.Cloud.Cmdlets.psm1
Import-Module Az.Accounts
Connect-AzAccount
Set-AzContext -SubscriptionId $SubscriptionId 
Start-SitecoreAzureDeployment -Name $DeploymentId -Location $Location -ArmTemplateUrl "$SCTemplates/azuredeploy.json"  -ArmParametersPath $ParamFile  -LicenseXmlPath $LicenseFile  -SetKeyValue $Parameters