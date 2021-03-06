#######################################################################################################
# Description:  Script used when running 20.1-install-web.ps1 to provide supporting file and  
#               service functions like CalculateAppZipFile()
# Author:       ?? Rolf
# Last Edited:  2021-10-19 by George Briedenhann
# Warning:      Script gets used by at least 5 other scripts to perform different functions. 
#               This might break the whole setup. Proceed at your own peril.
#######################################################################################################
.(Join-Path $PSScriptRoot "99-colors.ps1") -command
.(Join-Path $PSScriptRoot "99-checkdotnetcore.ps1") -command

<# Load all dll required for check certificate signed function#>
function loadCertificateAssemblies () {
  try {
    $dllfolder = Join-Path $PSScriptRoot "dll"
    Add-Type -Path "$dllfolder\Microsoft.IdentityModel.Tokens.dll"
    Add-Type -Path "$dllfolder\System.IdentityModel.Tokens.Jwt.dll"
    Add-Type -Path "$dllfolder\Microsoft.IdentityModel.Logging.dll"
    Add-Type -Path "$dllfolder\Microsoft.IdentityModel.JsonWebTokens.dll"
    Add-Type -Path "$dllfolder\System.Security.Cryptography.X509Certificates.dll"
    return $true
  }
  catch {
    Write-Host -ForegroundColor $colorError "loadCertificateAssemblies failed"
    Write-Host -ForegroundColor $colorError "$($psitem.exception)"
    Write-Host -ForegroundColor $colorError "$($psitem.scriptstacktrace)"
    return $false
  }
}

<# create a signed jwt token, for testing of certificate. We use dummy data for it #>
function CreateJwtTokenSigned (
  [string] $tb = $null, $displayInfo = $false
) {
  try {
    if ($tb) {
      # rei@3.8.2020 we read certificate again
      $signingX509Certificate = Get-ChildItem -Path "cert:\LocalMachine\my\$tb" -Recurse | Where-Object { $_.HasPrivateKey -eq $true } | Select-Object -First 1
    }
    $signingCredentials = New-Object -TypeName Microsoft.IdentityModel.Tokens.X509SigningCredentials($signingX509Certificate, [Microsoft.IdentityModel.Tokens.SecurityAlgorithms]::RsaSha256)

    $nameId = "Test jwt Token"
    $iss = "iTWO4.0 Testing signing jwt creator"
    $aud = "i'm the authority"
    $nbf = Get-Date
    $exp = (Get-Date).AddMinutes(5)

    $nameIdClaim = New-Object System.Security.Claims.Claim("nameid", $nameId)
    $delegateClaim = New-Object System.Security.Claims.Claim("trustedfordelegation", "true")
    $claims = New-Object System.Collections.Generic.List[System.Security.Claims.Claim]
    $claims.Add($nameIdClaim)
    $claims.Add($delegateClaim)
    $header = New-Object -TypeName System.IdentityModel.Tokens.Jwt.JwtHeader($signingCredentials)
    # remove kid and x5t uncomment following 3 lines
    #$header.Clear()
    #$header.Add("alg", "RS256");
    #$header.Add("typ", "JWT");

    $payload = New-Object -TypeName System.IdentityModel.Tokens.Jwt.JwtPayload($iss, $aud, $claims, $nbf, $exp)
    $token = New-Object -TypeName System.IdentityModel.Tokens.Jwt.JwtSecurityToken($header, $payload)
    #$token = New-Object -TypeName System.IdentityModel.Tokens.Jwt.JwtSecurityToken($iss, $aud, $claims, $nbf, $exp, $signingCredentials)
    $tok = (New-Object -TypeName System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler).WriteToken($token)
    if ($displayInfo) {
      Write-Host -ForegroundColor green "Token=$tok"
    }
    return $tok
  }
  catch {
    Write-Host -ForegroundColor $colorError "CreateJwtTokenSigned failed:"
    Write-Host -ForegroundColor $colorError "$($psitem.exception)"
    Write-Host -ForegroundColor $colorError "$($psitem.scriptstacktrace)"
    Write-Host
    return $null
  }
}


function isEmptyorDefault {
  param (
    [string]$parameter,
    [string]$default = $null
  )
  if ($parameter -and $($parameter.Trim().Length -gt 0) -and ($null -eq $default -or ($null -ne $default -and ($parameter -ne $default) ))) {
    return $false
  }
  return $true
}

<# this function checks redumentary config file parameters #>
function CheckConfigParameter {

  $checkfailed = $false
  # license Key
  if (-not ($license_subscriptionId -and $license_subscriptionSign -and $($license_subscriptionId.Trim().Length -gt 0) -and $($license_subscriptionSign.Trim().Length -gt 0))) {
    Write-Host -ForegroundColor $colorError "License Data in Config missing. Installation aborted"
    $checkfailed = $true
  }
  if ( $(isEmptyorDefault $username "{serviceuser username}") -and $(isEmptyorDefault $password "{serviceuser password}")) {
    Write-Host -ForegroundColor $colorError "Serviceuser >> Username / Password in Config missing. Installation aborted"
    $checkfailed = $true
  }

  return (-not $checkfailed)
}

<#
  This function replace the office 365 parameters in config.js
  rei@04.02.2021
#>
function ConfigJsReplaceOfficeIntegrationParameter {
  param (
    [string]$configjscontent,
    [string]$authorityUrl = "https://login.microsoftonline.com",
    [string]$tenant = "common",
    [string]$office365clientid = $null,
    [string]$msgraphUrl = "https://graph.microsoft.com",
    [string]$skypeUrl = "https://webdir.online.lync.com",
    [string]$officeViewerServerUrl = "https://view.officeapps.live.com"
  )
  #   $sample= @'
  #  aad: {
  #  	authority: 'https://login.microsoftonline.com',
  #  	tenant: 'common',
  #  	office365ClientId: '8851e90d-306a-4475-903c-704c54a1c4a1',
  #  	resource:{
  #  		msGraph: 'https://graph.microsoft.com',
  #  		skype: 'https://webdir.online.lync.com'
  #  	}
  #  },
  #'@

  # groups         (   $1                    )($2) (  $3           )($4) ( $5                      )($6 )(  $7                           )($8 )( $9            )($10)( $11                               )($12)($13)
  $pattern = "(?ms)(.*aad:.*{.*authority:\s*')(.*?)(',.*tenant:\s*')(.*?)(',.*office365ClientId:\s')(.*?)(',.*resource:\s*{.*msGraph:\s*')(.*?)(',\s*skype:\s*')(.*?)('\s*},\s*officeViewerServerUrl:\s*')(.*?)('.*)"

  $result = $configjscontent -replace $pattern, '$1%authority%$3%tenant%$5%office365clientid%$7%msgraph%$9%skype%$11%officeViewerServerUrl%$13'
  $result = $result.replace('%authority%', $authorityUrl)
  $result = $result.replace('%tenant%', $tenant)
  $result = $result.replace('%office365clientid%', $office365clientid)
  $result = $result.replace('%msgraph%', $msgraphUrl)
  $result = $result.replace('%skype%', $skypeUrl)
  $result = $result.replace('%officeViewerServerUrl%', $officeViewerServerUrl)

  # validate if replacement was working
  if ($result.IndexOf("'$authorityUrl'") -gt 0 ) {
    if ($result.IndexOf("'$msgraphUrl") -gt 0) {
      if ($result.IndexOf("'$skypeUrl") -gt 0) {
        if ($result.IndexOf("'$office365clientid") -gt 0) {
          if ($result.IndexOf("'$tenant") -gt 0) {
            Write-Host -ForegroundColor $colorinfo "OfficeIntegrationParameter validation in config.js passed. ok."
            return $result
          }
        }
      }
    }
  }
  Write-Host -ForegroundColor $colorError "OfficeIntegrationParameter set in config.js failed! Please verify!!"
  return $null
}

<#
  This function replace the i18ncustom property with true|false $isActive by parameter value
  rei@10.07.2020
#>
function ConfigJsReplacei18NCustom {
  param (
    [string]$configjscontent,
    [string]$isActive = $false
  )

  # groups         ( $1             )(    $2    )($3 )
  $private:pattern = "(?ms)(.*i18nCustom:\s*)(false|true)(,.*)"
  $private:result = $configjscontent -replace $private:pattern, '$1%i18nvalue%$3'
  $private:result = $private:result.replace('%i18nvalue%', $(if ($isActive) { "true" }else { "false" } ) )
  # validate if replacement was working
  Write-Host -ForegroundColor $colorinfo "Override of i18NCustom text set in config.js >>> i18nCustom='$isActive'"
  return $private:result
}

<# added rei@28.9.2020 #>
function ConfigJsReplaceUserlanePropertyId {
  param (
    [string]$configjscontent,
    [string]$userlanePropertyId
  )

  # groups                 ( $1                 )( $2 )($3 )
  $private:pattern = "(?ms)(.*userlanePropertyId:\s*)('.*?')(,.*)"
  $private:result = $configjscontent -replace $private:pattern, '$1%userlanePropertyId%$3'
  $private:result = $private:result.replace('%userlanePropertyId%', "'$userlanePropertyId'" )
  # validate if replacement was working
  Write-Host -ForegroundColor $colorinfo "UserlanePropertyId text set in config.js >>> userlanePropertyId='$userlanePropertyId'"
  return $private:result
}

<#
  This function replace the  dashboard.url property with the $url parameter value
  rei@18.6.2020
#>
function ConfigJsReplaceDatapineUrl {
  param (
    [string]$configjscontent,
    [string]$url = $null,
    [string]$ssocallbacktoken = "itwo40"  ## rei@18.6.20 currently value is fixed
  )

  #   $sample= @'
  #   @dashboard:{
  #       url: 'https://admin-datapine.rib-software.com/mvc/organizations/W3DoFlMPcyyUEoi9ZWAK4',
  #       ssoCallbackKey: 'itwo40'
  #   },
  #'@

  # groups         ( $1                       )($2)(   $3                  )($4)( $5  )
  $pattern = "(?ms)(.*dashboard:\s*{.*url:\s*')(.*?)(',.*ssoCallbackKey:\s*')(.*?)('.*)"
  $result = $configjscontent -replace $pattern, '$1%url%$3%token%$5'
  $result = $result.replace('%url%', $url)
  $result = $result.replace('%token%', $ssocallbacktoken)

  # validate if replacement was working
  if ($result.IndexOf("'$url'") -gt 0 ) {
    if ($result.IndexOf("'$ssocallbacktoken") -gt 0) {
      Write-Host -ForegroundColor $colorinfo "datapine Url set in config.js >>> url='$datapineiframeurl', token='$ssocallbacktoken'"
      return $result
    }
  }
  Write-Host -ForegroundColor $colorError "datapine Url set in config.js failed! Please verify"
  return $null
}

<#
    Test Code here...
    # $rootfolder = "D:\itwo40_400\"
    # $accessright = "read"
    # $username = "superuser"
    # SetFolderAccessRightsToServiceUser -username $username -accessright $accessright -rootfolder $rootfolder
    rei@17.6.2020 added
    #>
function SetFolderAccessRightsToServiceUser {
  param(
    [string]$userName = "superuser",
    $accessright = "Read",
    [string]$rootfolder
  )

  $username = "superuser"
  $accessright = "Read"
  #$rootfolder = $installfolder
  $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($username, "Read", "Allow")
  $AccessRuleWrite = New-Object System.Security.AccessControl.FileSystemAccessRule($username, "Write", "Deny")
  $acl = Get-Acl $rootfolder
  $acl.SetAccessRule($AccessRule)
  $acl.AddAccessRule($AccessRuleWrite)

  <#To manage inheritance, we use the “SetAccessRuleProtection” method. It has two parameters:
      The first parameter is responsible for blocking inheritance from the parent folder.
      It has two states: “$true” and “$false”.
      The second parameter determines whether the current inherited permissions are retained or removed.
      It has the same two states: “$true” and “$false”.
  #>
  #$acl.SetAccessRuleProtection($false,$true) # rei@17.6.2020 Let’s disable inheritance $rootfolder folder and delete all inherited permissions
  $acl | Set-Acl $rootfolder
}


function CheckCertificateAccessforServiceUser {

  setactoUserforCertificate -username $username -certThumbprint $identityServerCertificateFingerPrint

}

function setactoUserforCertificate {
  param($userName, $certThumbprint)

  $certStoreLocation = "Cert:\\LocalMachine\My" # fixed store, always there
  $certificate = Get-ChildItem $certStoreLocation | Where-Object thumbprint -EQ $certThumbprint

  if ([string]::IsNullOrEmpty($certificate.PrivateKey)) {
    $rsaCert = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($certificate)
    $fileName = $rsaCert.key.UniqueName
    $path = "$env:ALLUSERSPROFILE\Microsoft\Crypto\Keys\$fileName"
    $permissions = Get-Acl -Path $path
    $access_rule = New-Object System.Security.AccessControl.FileSystemAccessRule($userName, 'Read', 'None', 'None', 'Allow')
    $permissions.AddAccessRule($access_rule)
    Set-Acl -Path $path -AclObject $permissions
    Write-Host -ForegroundColor $colorInfo "Certificate Accessright(Acl) set to read for CertThumbprint=$certThumbprint"
  }
  else {
    $user = New-Object System.Security.Principal.NTAccount($userName)
    $accessRule = New-Object System.Security.AccessControl.CryptoKeyAccessRule($user, 'GenericRead', 'Allow')
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store("My", "LocalMachine")
    $store.Open("ReadWrite")
    $rwCert = $store.Certificates | Where-Object { $_.Thumbprint -eq $certificate.Thumbprint }
    $csp = New-Object System.Security.Cryptography.CspParameters($rwCert.PrivateKey.CspKeyContainerInfo.ProviderType, $rwCert.PrivateKey.CspKeyContainerInfo.ProviderName, $rwCert.PrivateKey.CspKeyContainerInfo.KeyContainerName)
    $csp.Flags = "UseExistingKey", "UseMachineKeyStore"
    $csp.CryptoKeySecurity = $rwCert.PrivateKey.CspKeyContainerInfo.CryptoKeySecurity
    $csp.KeyNumber = $rwCert.PrivateKey.CspKeyContainerInfo.KeyNumber
    $csp.CryptoKeySecurity.AddAccessRule($AccessRule)
    $_rsa2 = New-Object System.Security.Cryptography.RSACryptoServiceProvider($csp)
    $store.close()
    Write-Host -ForegroundColor $colorInfo "Certificate Accessright(AccessRule) set to read for CertThumbprint=$certThumbprint"
  }
}

function setactoUserforCertificate_old {
  param(
    [string]$userName,
    [string]$certThumbprint
  )
  # check if certificate is already installed
  $certStoreLocation = "Cert:\\LocalMachine\My" # fixed store, always there
  $permission = "read" # read access is good for use
  $certificateInstalled = Get-ChildItem $certStoreLocation | Where-Object thumbprint -EQ $certThumbprint

  # download & install only if certificate is not already installed on machine
  if ($null -eq $certificateInstalled) {
    $message = "Certificate with thumbprint:" + $certThumbprint + " does not exist at Store: " + $certStoreLocation
    Write-Host $message -ForegroundColor $colorError
    return 1
  }
  else {
    try {
      $message = "Certificate with thumbprint: $certThumbprint found at " + $certStoreLocation
      Write-Host -ForegroundColor $colorInfo $message
      $rule = New-Object security.accesscontrol.filesystemaccessrule $userName, $permission, allow
      $root = "c:\programdata\microsoft\crypto\rsa\machinekeys"
      $certificateInstalled | ForEach-Object {
        $keyname = $_.privatekey.cspkeycontainerinfo.uniquekeycontainername
        $p = [io.path]::combine($root, $keyname)
        if ([io.file]::exists($p)) {
          $acl = Get-Acl -Path $p
          $acl.addaccessrule($rule)
          Set-Acl $p $acl
          Write-Host -ForegroundColor yellow "Certificate Read Access assigned to User: '$userName'"
        }
      }
    }
    catch {
      Write-Host -ForegroundColor Red "Caught an exception: $($_.Exception)"
      return 1
    }
  }
}


Function RebuildClientBundles (
  [string] $p1) {

  $_clientPath = Join-Path $iisRootPath "client"
  Write-Host "Rebuilding Client Bundle in Folder $_clientPath" -ForegroundColor Yellow  # don't use var, because it' used before

  Push-Location $_clientPath
  gulp build --development --debug --minimize
  Pop-Location
  Write-Host "Rebuilding Client Bundle done..." -ForegroundColor Yellow  # don't use var, because it' used before
}

Function ValidateCertificate(
  [string] $thumbprint) {
  if ("" -eq $thumbprint) {
    Write-Host "Validation of Certificate failed, not Thumbprint defined!" -ForegroundColor $colorError
    return $false
  }
  $failedMsg = "Certification Validation Thumbprint=$thumbprint failed!"
  $_c = Get-ChildItem -Path cert:\LocalMachine\my\$thumbprint -ErrorAction Ignore
  if ($_c) {
    $cDate = Get-Date

    if ($_c.NotAfter -le $cDate) {
      Write-Host "$failedMsg The Certificate expired on $($_c.NotAfter)." -ForegroundColor $colorError
      Write-Host "Please replace Certificate with a valid one." -ForegroundColor $colorError
      return $false
    }
    if (-not $_c.HasPrivateKey) {
      Write-Host "$failedMsg Private Key not found." -ForegroundColor $colorError
      Write-Host "Please check Accessright to Certificate or you are using a wrong Certificate type, without private key." -ForegroundColor $colorError
      return $false
    }
    else {
      Write-Host -ForegroundColor $colorInfo "Certificate Validation Thumbprint=$thumbprint passed. Valid until $($_c.NotAfter)"

      # rei@3.8.2020 now check certificate jwt
      if ($certficatetestingenabled) {
        Write-Host -ForegroundColor $colorInfo "Certificate testing enabled: Test jwt generation in process ..."
        $_loaded = loadCertificateAssemblies  # load required assemblies for checking
        if ($_loaded) {
          $_tok = CreateJwtTokenSigned -tb $thumbprint -displayinfo $false
          if ($_tok) {
            Write-Host -ForegroundColor $colorInfo "Certificate jwt generation testing successfully passed."
          }
        }
      }
      return $true
    }
  }
  else {
    Write-Host "$failedMsg Certificate not found!" -ForegroundColor $colorError
    return $false
  }
}

function readConsole() {
  try {
    $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
  }
  catch {
    $x = @{character = "y" }
  }
  if ($x.character -eq "y") {
    return $true
  }
  return $false
}


<# Create Servie User and add him o the administrator group #>
function CheckCreateLocalServiceUser (
  $checkcreate = $null,
  [string] $username,
  [string] $password,
  [bool] $addtoAdminGroup
) {
  if ($checkcreate) {
    CreateLocalServiceUser -username $username -password $password -addtoAdminGroup $addtoAdminGroup -addtoAuthUserGroup $true
  }
}

<#
This method parsed the "to be registered renderserver list"  $renderClusterRegisterRenderServer
into the RenderCluster Section required xml <url> element list
#>
function ParseCustomerAppSettingsExtensions {
  param (
    $appsettingkeyvaluelist = $null,
    [string] $webconfigfullfilename = $null
  )

  # check input parameters
  if (-not $appsettingkeyvaluelist) { return "" }
  if ($appsettingkeyvaluelist.GetType().Name -ne "Object[]") {
    Write-Host -ForegroundColor $colorError "Wrong parameter type "'$appsettingkeyvaluelist'$($appsettingkeyvaluelist.GetType().Name)
    return ""
  }
  if (-not $webconfigfullfilename) {
    Write-Host -ForegroundColor $colorError "Wrong parameter web.config not defined"
    return ""
  }

  Write-Host "Process Customer Appsetting for web.config $webconfigfullfilename" -ForegroundColor $colorinfo
  # Get the content of the config file and cast it to XML and save a backup copy labeled .bak followed by the date
  $xml = [xml](Get-Content $webconfigfullfilename)
  #$xml.Save($webConfigPath + '.sav')

  $root = $xml.get_DocumentElement();
  $apps = $root.appSettings.add
  foreach ($i in $appsettingkeyvaluelist) {
    #$item = '<url url="{0}" apikey="{1}" /> <!-- activate a specific render server (from config file) -->'
    Write-Host "Override or Insert AppSetting Element: Key=$($i.key) Value=$($i.value)" -ForegroundColor $colorInfo
    SetAppKeyValue -appRoot $root.appSettings -appSettings $apps -appkey $i.key -appNewValue $i.value
  }
  # Save it
  $xml.Save($webconfigfullfilename)
}

<#
This method parsed the "to be registered renderserver list"  $renderClusterRegisterRenderServer
into the RenderCluster Section required xml <url> element list
#>
function ParseSchedulerApplicationIdToExecutionGroup {
  param (
    $content
  )
  # check input parameters
  if (-not $SchedulerApplicationIdToExecutionGroup) { return "" }

  if ($SchedulerApplicationIdToExecutionGroup.GetType().Name -ne "Object[]") {
    Write-Host -ForegroundColor $colorError "Wrong parameter type "'$SchedulerApplicationIdToExecutionGroup'$($SchedulerApplicationIdToExecutionGroup.GetType().Name)
    return ""
  }
  Write-Host "Process Scheduler ApplicationId to ExecutionGroup webconfigfullfilename" -ForegroundColor $colorinfo

  foreach ($i in $SchedulerApplicationIdToExecutionGroup) {
    #$item = '<url url="{0}" apikey="{1}" /> <!-- activate a specific render server (from config file) -->'
    $_schedulerappidkey = "scheduler:appid.$($i.key)"
    Write-Host "Override or Insert AppSetting Element: Key=$_schedulerappidkey Value=$($i.value)" -ForegroundColor $colorInfo
    SetObjectMember -in $content.AppSettings -member $_schedulerappidkey -value $i.value
  }
}

<#
SID: S-1-5-32-544
Name: Administrators
Description: A built-in group. After the initial installation of the operating system, the only member of the group is the Administrator account. When a computer joins a domain, the Domain Admins group is added to the Administrators group. When a server becomes a domain controller, the Enterprise Admins group also is added to the Administrators group.
#>
function CreateLocalServiceUser(
  [string] $username,
  [string] $password,
  [bool] $addtoAdminGroup = $true,
  [bool] $addtoAuthUserGroup = $true
) {

  $usr = Get-LocalUser $username -ErrorAction ignore
  if (-not $usr) {
    Write-Host "User $username not existing" -ForegroundColor yellow
    $pwd = ConvertTo-SecureString -AsPlainText -Force $password
    $usr = New-LocalUser $username -Password $pwd -FullName "" -Description "account created while itwo40 installation." -PasswordNeverExpires
  }
  else {
    Write-Host "User $username already exists" -ForegroundColor yellow
  }

  if ($usr -and $addtoAuthUserGroup) {
    $ismember = Get-LocalGroupMember -SID "S-1-5-32-545" -Member $username -ErrorAction ignore
    if (-not $ismember) {
      Write-Host "Add User $username to Users" -ForegroundColor yellow
      Add-LocalGroupMember -SID "S-1-5-32-545" -Member $username
    }
    else {
      Write-Host "User $username already member of Users" -ForegroundColor yellow
    }
  }

  if ($usr -and $addtoAdminGroup) {
    $ismember = Get-LocalGroupMember -SID "S-1-5-32-544" -Member $username -ErrorAction ignore
    if (-not $ismember) {
      Write-Host "Add User $username to Administrators" -ForegroundColor yellow
      Add-LocalGroupMember -SID "S-1-5-32-544" -Member $username
    }
    else {
      Write-Host "User $username already member of Administrators" -ForegroundColor yellow
    }
  }

}

<# create a new local service user #>
function RemoveServiceUser(
  [string] $username
) {
  $usr = Get-LocalUser $username -ErrorAction ignore
  if ($usr) {
    Write-Host "User $username will be deleted" -ForegroundColor yellow
    $usr = Remove-LocalUser $username
  }
}

##############################
# This method check credentials for user, throw an error if login failed
#.PARAMETER username
#Parameter $username, $password
#.PARAMETER pwd
#Parameter description
##############################
function CheckDatengutServer () {

  $daguUrl = "https://ecm.datengut.de/daguweb/rest/logonmethods"
  $daguName= "Datengut License Server"
  Try {

      #Initiating Send
      Write-Host "Check $($daguName): $daguUrl" -ForegroundColor $colorInfo
      $result = Invoke-WebRequest -UseBasicParsing -uri $daguUrl
      if ($result.StatusCode -eq 200) {
          Write-Host " $daguName Validation sucessfully done." -ForegroundColor $colorOk
      } else {
          throw "$daguName failed with $($result.StatusCode) $($result.StatusDescription)"
      }
  }
  Catch {
      #write-host "Error: $_"
      #Throw $ReturnXml.Envelope.InnerText
      Write-Host "Access validation to $daguName failed!" -ForegroundColor $colorWarning
      Write-Host " Error Info: $_" -ForegroundColor $colorWarning

      Write-Host ""
      Write-Host "S T A R T  H i n t  for fixing issue with $daguName"-ForegroundColor $colorWarning
      Write-Host " Please make sure your server can access the $daguName." -ForegroundColor $colorWarning
      Write-Host " Url: $URL" -ForegroundColor $colorWarning
      Write-Host " Please open your firewall for access to the $daguName url" -ForegroundColor $colorWarning
      Write-Host " At the moment you can continue with your server installation, " -ForegroundColor $colorOk
      Write-Host " but for future installation the server might quit up work, without having access to above url" -ForegroundColor $colorOk

      Write-Host "H i n t  end."-ForegroundColor $colorWarning
      Write-Host ""
      return
  }
  Write-Host "Check $daguName done."-ForegroundColor $colorInfo
}


##############################
# This method check credentials for user, throw an error if login failed
#.PARAMETER username
#Parameter $username, $password
#.PARAMETER pwd
#Parameter description
##############################
function CheckUserCredentials (
  [Parameter(Mandatory = $true)][string]$username,
  [Parameter(Mandatory = $true)][string]$password
) {
  if ($SuppressCheckCredentials) {
    Write-Host "iTWO4.0 Service User Account Validation suppressed." -ForegroundColor $colorImportant
    return $true
  }
  $_svcUserValid = CheckCredentials -username $username -password $password
  if (!$_svcUserValid) {
    $errmsg = "iTWO4.0 Service User Account $username Validation failed! Please check!"
    throw $errmsg
  }
  else {
    Write-Host "iTWO4.0 Service User Account $username Validation successfully checked." -ForegroundColor $colorOkLow
  }
}

###############################################################################
## CheckConfigFile: check for correct version of config file
## sample:
##	CheckConfigFile
###############################################################################
function CheckConfigFile () {
  $requestedCfgVersion = 11
  if ($configfileversion -ne $requestedCfgVersion) {
    Write-Host "Wrong Configfile found. Please migrate to latest version. Cannot continue...`n Info: current version: $configfileversion  requested version: $requestedCfgVersion" -ForegroundColor $colorError
    Write-Host "S t a r t  o f  h i n t "-ForegroundColor $colorwarning
    Write-Host "   Save your current configfile i.e. rename it, and copy from:"-ForegroundColor $colorwarning
    Write-Host "   ..\00-setup\scripts\00-config-itwo40.ps1 into your <customscripts> folder."-ForegroundColor $colorwarning
    Write-Host "   After that, merge your settings from your previous config file into a new config file: 00-config-itwo40.ps1 "-ForegroundColor $colorwarning
    Write-Host "   Then restart deployment."-ForegroundColor $colorwarning
    Write-Host "E n d  o f  h i n t "-ForegroundColor $colorwarning
    Write-Host ""
    $script:abortInstallation = $true
    exit
  }
}

###############################################################################
## checkOtherConfigFileParameter: check for several configparameters
###############################################################################
function checkOtherConfigFileParameter () {

  $private:abort = $false
  # validate max. path length
  if ($($itwo40UrlPath + $itwo40UrlSubPath).length -gt 28) {
    Write-Host "S t a r t  o f  h i n t "-ForegroundColor $colorwarning
    Write-Host -ForegroundColor $colorError "  Length of `$itwo40UrlPath+`$itwo40UrlSubPath mustn't be longer than 28 character!"
    Write-Host -ForegroundColor $colorError "  Otherwise while copying executables into temporary Internet Information Server folder might fail."
    Write-Host -ForegroundColor $colorError "  Fix length of the variables and start deployment again."
    Write-Host "E n d  o f  h i n t "-ForegroundColor $colorwarning
    $private:abort = $true
  }
  if ($private:abort) {
    $script:abortInstallation = $true
    exit
  }
}

<# # helper test function for above checkOtherConfigFileParameter
function test () {
  $colorError = "red"
  $colorwarning = "magenta"
  $itwo40UrlPath="itwo40"
  $itwo40UrlSubPath="01234567890123456789012"
  checkOtherConfigFileParameter
}
#>
function SetObjectMember {
  Param(
    [Parameter(Mandatory = $true)]$in,
    [Parameter(Mandatory = $true)]$member,
    [Parameter(Mandatory = $true)]$value,
    $default = "" )
  $private:val = $default
  if (-not [string]::IsNullOrWhiteSpace($value)) {
    $private:val = $value
  }
  Add-Member -MemberType noteproperty -Force -InputObject $in -Name $member -Value $private:val
}

######################################
## CheckConfigFile for valid license
## sample:
##	CheckLicense
###############################################################################
function CheckLicense () {
  ## check setting of license keys  rei@25.6.18
  if ([string]::IsNullOrEmpty($license_subscriptionId) -eq $true -or [string]::IsNullOrEmpty($license_subscriptionSign) -eq $true) {
    Write-Host "License Issue: Deployment aborted because License SubscriptionId or Signature are missing. Please verify!" -ForegroundColor $colorError
    $script:abortInstallation = $true
    exit
  }
}

######################################
## CheckAESKey check for valid AES Key
## sample:
##	CheckAESKey
###############################################################################
function CheckAESKey () {

  # generate synthetic AES key with GUID if not supplied
  if ([string]::IsNullOrEmpty($appServerAesKey) -eq $true) {
    Write-Host "AES Key is not valid: The AES key is used for encrypting passwords in the database,`nyou must supply a valid value! Installation aborted!" -ForegroundColor $colorError
    $script:abortInstallation = $true
    exit
  }
}

######################################
## CheckAESKey check for valid AES Key
## sample:
##	CheckAESKey
###############################################################################
function CheckReportingUser () {

  if ($null -eq $enablereportinguser) {
    if (($reportingdbusername -eq "{reporting sql auth login name}" ) -or ($reportingdbpassword -eq "{reporting sql login password}") ) {
      Write-Host -ForegroundColor $colorError "Reporting User Settings failed!`nFor Security Reason we request since version Release 5.1 an extra SQL database user for Serving Reports."
      Write-Host -ForegroundColor $colorError "`nYou must set the reporting parameter: `$reportingdbusername & `$reportingdbpassword other from null or `"`" or default values."
      $script:abortInstallation = $true
      exit
    }
  }
  if ($enablereportinguser -eq 0) {
    Write-Host -ForegroundColor $colorError "Reporting User Settings failed!`nFor Security Reason we request since version Release 5.1 an extra SQL database user for Serving Reports."
    Write-Host -ForegroundColor $colorError "Please remove parameter: `$enablereportinguser from config file, and define valid `$reportingdbusername & `$reportingdbpassword parameters."
    $script:abortInstallation = $true
    exit
  }
}

###############################################################################
## CleanFileOlderThan
## sample:
##	CleanFileOlderThan -folder "c:\temp\reports" -filename "*.fpx" -hours 12 -days 1
###############################################################################
function CleanFileOlderThan(
  [string]$folder,
  [string]$filename = "*.*",
  [int]$days = 0,
  [int]$hours = 0
) {
  $Now = Get-Date
  $LastWrite = $Now.AddDays( - $Days).AddHours( - $hours)

  #----- get files based on lastwrite filter and specified folder ---#
  $Files = Get-ChildItem $folder -Include $filename -Recurse | Where-Object { $_.LastWriteTime -le "$LastWrite" }
  if ($Files -eq $null ) {
    Write-Host "No files found: '$folder\$filename'"
  }
  else {
    Write-Host "Start deletion of older file before $lastWrite", "\t'$folder\$filename' files"
  }
  foreach ($File in $Files) {
    if ($File -ne $NULL) {
      Write-Host "Deleting File $File" -ForegroundColor "DarkRed"
      Remove-Item $File.FullName | Out-Null
    }
    else {
      Write-Host "No more files to delete!" -ForegroundColor "Green"
    }
  }
}

Function IIfElse($If, $IfFalse = $null) {
  if ($If) { if ($If -is "ScriptBlock") { &$If } Else { $If } }
  Else { If ($IfFalse -is "ScriptBlock") { &$IfFalse } Else { $IfFalse } }
}

Function IIf($If, $IfTrue, $IfFalse) {
  if ($If) { if ($IfTrue -is "ScriptBlock") { &$IfTrue } Else { $IfTrue } }
  Else { If ($IfFalse -is "ScriptBlock") { &$IfFalse } Else { $IfFalse } }
}


function CreateDirectory([string]$folder, $showInfo = $false) {

  if (-not(Test-Path -Path $folder)) {
    if ($showInfo) {
      Write-Host "Folder $folder not existing -> create it." -ForegroundColor $colorInfoLow
    }
    $_ret = New-Item -Path $folder -Type Directory
    return $true
  }
  return $false
}

function CleanDirectory([string]$folder) {
  if (Test-Path -Path $folder) {
    # not use this method because symbolic link are delete correctly
    #$value=[System.IO.Directory]::Delete($folder,$true)
    ##write-host cmd /c rmdir /s/q "$folder"
    &cmd /c "rmdir /s/q ""$folder"""
  }
}

function DeepCleanDirectory(
  [string]$folder,
  [bool]$info = $true,
  [bool]$optionTest = $true) {
  if ($optionTest) {
    if (Test-Path -Path $folder) {
      if ($info) {
        Write-Host "Cleanup in process $folder"
      }
      # not use this method because symbolic link are delete correctly
      #$value=[System.IO.Directory]::Delete($folder,$true)
      ##write-host cmd /c rmdir /s/q "$folder"
      &cmd /c "rmdir /s/q ""$folder"""
      if (Test-Path -Path $folder) {
        Write-Host -ForegroundColor magenta "Cleanup of folder $folder was not complete successful, try again!"
        Start-Sleep 10
        &cmd /c "rmdir /s/q ""$folder"""
        if (Test-Path -Path $folder) {
          Write-Host -ForegroundColor magenta " 2nd Cleanup of folder $folder was not complete! Check the target folder!"
        }
      }
    }
  }
}

function DeleteFileIfExist([string]$file, [bool]$showinfo = $true) {

  if (Test-Path $file) {
    Remove-Item -Force -Path $file
    if ($showinfo) { Write-Host -ForegroundColor $colorInfo "File $file deleted." }
    return $true
  }
  return $false
}

function CleanOrCreateDirectory([string]$folder) {

  if (-not(Test-Path -Path $folder)) {
    $_ret = New-Item -Path $folder -Type Directory
    return $true
  }
  else {
    Remove-Item -Recurse -Path $folder'\*.*'
    return $false
  }
}

function CurrentTime() {
  return (Get-Date).ToLongTimeString()
}

function CurrentDateTime() {
  return (Get-Date).ToShortDateString() + " " + (Get-Date).ToLongTimeString()
}

function CurrentDate() {
  return (Get-Date).ToShortDateString()
}

function pause () {
  Write-Host "Press any key to continue ..."
  $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

#############################################
#.PARAMETER applzipfiles   setup folder containing the applzipfiles folder
#.PARAMETER theConfiguration  the configuration: default "Release"

<# find the latest application zipfile from application folder #>

function CalculateAppZipFile {
  param(
    [string]$applzipfiles,
    [string]$theConfiguration = "Release"
  )
  ### define source zip stuff
  ## The directories are in format '1.0.357.318886', we sort ascending and take the last one.
  Write-Host "Check latest application zip file folder Config=$theConfiguration ..."
  
  #NOTE: GPB - Removed version file sorting
  # $_lastVersion = Get-ChildItem $applzipfiles | Where-Object {   $_.name -match "\d+[.]\d+[.]\d+[.]\d+" } | ForEach-Object { $_.name } | Sort-Object | Select-Object -Last 1
  # $_latestBinPoolPath = Join-Path $applzipfiles $_lastVersion
  
  # NOTES: GPB 
  #   - Rely on date sorting and not version number due to international version number different from dach. 
  #   - Exclude maintanace and base folders due to deployment automation not neccesaraly creating the target folder last.
  #   - TODO: maybe add nullable param for function and switch between regex for dach and int. versions.
  $_lastVersion = Get-ChildItem $applzipfiles | Where-Object { $_.PSIsContainer -and $_.FullName -notmatch 'maintenance' -and $_.FullName -notmatch 'base' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $_latestBinPoolPath = Join-Path $applzipfiles $_lastVersion

  Write-Host "latest application zip file folder=$_latestBinPoolPath" -ForegroundColor Green
  return $_latestBinPoolPath
}

function ParseVersionInfo() {
  <# process product version info from applzipfiles folder #>
  ## read product version (again) from json file and put it into web.config for usage in program
  $script:revisioninfo = (Get-Content (Join-Path $latestBinPoolPath "revision.json")) -join "`n" | ConvertFrom-Json
  $script:prodversionjson = (Get-Content (Join-Path $applzipfiles "productversion.json")) -join "`n" | ConvertFrom-Json

  $script:productVersion = "$($prodversionjson.productVersion)"
  $script:buildversion = "$($revisioninfo.label)"
  $script:additionalInfo = "$($prodversionjson.additionalInfo)"

  $script:productdate = Get-Date($revisioninfo.isoCreationDate) -Format "s" # ISO 8601 format
  $script:installationdate = Get-Date -Format "s" # ISO 8601 format

  ## rei@29.6.18 allow override of product version
  if ([string]::IsNullOrEmpty($overrideprodversion) -eq $false) {
    Write-Host "Override Productname with own Name '$overrideprodversion'"-ForegroundColor $colorInfo
    $script:productVersion = "$overrideprodversion"
  }
  Write-Host "Parsed Version: ProductVersion: $script:productVersion, BuildVersion: $script:buildversion, ProductDate: $script:productdate, InstallationDate: $script:installationdate" -ForegroundColor Cyan
}

########################################################################
#Change dynamic compression in IIS Services for folder $ServicesPath
########################################################################
function SetDynamicCompression([string] $ServicesPath) {
  $cfgfile = $ServicesPath + "\web.config"
  if (Test-Path -Path $cfgfile) {
    $file = Get-Item -Path $cfgfile

    # Get the content of the config file and cast it to XML to easily find and modify settings.
    $xml = [xml](Get-Content $file)
    Write-Host $xml.configuration.Item("system.webServer").Item("urlCompression")
    $xml.configuration.Item("system.webServer").Item("urlCompression").SetAttribute("doDynamicCompression", "true")
    Write-Host $xml.configuration.Item("system.webServer").Item("urlCompression")
    $xml.Save($file.FullName)
  }
}

<#this method returns the plain password from a byte array string secure password#>
function getPlainStringFromSecureTextString ([string] $securestringtext) {

  <#$password="test24523432432423423dasdqadsadaedwqedwqewqe"
  $SecureString = $password  | ConvertTo-SecureString -asplaintext -force
  $SecureStringAsPlainText = $SecureString | ConvertFrom-SecureString
  #$securestrFromSaved=$SecureStringAsPlainText | ConvertTo-SecureString #>
  $_securestring = ConvertTo-SecureString $securestringtext
  $_bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
  $_plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
  return $_plainPassword
}

function DefaultP {
  $enc = '76492d1116743f0423413b16050a5345MgB8AEUAZAAzADYASgBlAEcAOQBqAFUAeABCADcANAA4AE0ARwBNAGQAcwBtAGcAPQA9AHwAYQBlADQANgA3ADQAMQBjAGMAOAAwADUAOQA5AGIAYwAwADIANABhADMAYwAwAGMANAAzAGMAMAAwADMAZQAxAGMANAA0ADUAMwBhADMAYwA3AGYAYgBkADkAMABjAGQAYgAxAGQANQAxADkAYgBlADAAYQA1AGIANgA5AGUAMQA='
  $Key = (43, 24, 52, 63, 156, 234, 254, 222, 15, 123, 245, 56, 231, 50, 98, 45)
  #$enc = ConvertFrom-SecureString $(ConvertTo-SecureString "thepassword" -AsPlainText -Force) -Key $Key
  $Secure = ConvertTo-SecureString $enc -Key $Key
  $plainPwd = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto( $([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)))
  #Write-Host $plainPwd
  return $plainPwd
}

function DefaultPasswordInfo {
  $infoTxt = @'
--- I n f o   I n f o   I n f o   I n f o   I n f o   I n f o    --------------
iTWO4.0 Standard User ribadmin default password was changed. 
It will be now an One-Time Password! The One-Time password must
be changed after your first login - keep the new password at a safe place.

Password Info:  user: ribadmin  pwd: {0}

Remark: If this is a Update Installation you can change the ribadmin password with
        the powershell script 20.99-changeuserpassword.ps1
Please log in to iTWO4.0 with the user ribadmin and change the password now!
{1}
'@
  $theInfoText = $infoTxt -f $(DefaultP),$('-'*80)
  write-host -ForegroundColor $colorInfo $theInfoText 
  return '' #$theInfoText
}


######################################################################
#0: 	OK
#1: 	OK Cancel
#2: 	Abort Retry Ignore
#3: 	Yes No Cancel
#4: 	Yes No
#5:
######################################################################
function MessageBox ([string] $title, [string] $text, [int] $boxtype = 0, [bool] $interactive = $true) {

  if ($interactive) {
    $_load = [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    $OUTPUT = [System.Windows.Forms.MessageBox]::Show($text , $title, $boxtype)
    return $output
  }
  else {
    Write-Output $title, $text
  }
}

function ExtractZipFile (
  [string] $zipFile,
  [string] $outFolder,
  [string] $zipexe,
  $zipOptions, # must be an string array
  [bool] $showCmd = $false ) {

  $Time = [System.Diagnostics.Stopwatch]::StartNew()
  Write-Host "Extracting: $zipFile to $outFolder" -ForegroundColor Gray
  if ($showCmd -eq $true) {
    Write-Host $zipexe -p x -r -y -aoa -o"$outFolder" $zipOptions $zipFile -ForegroundColor Gray
  }
  $_result = &$zipexe -p "x" -mmt100 -r -y -aoa -o"$outFolder" $zipOptions $zipFile | Out-String
  $elapsedSec = "$(($Time.Elapsed).TotalSeconds) sec"
  $Time = $null
  if ($_result -match "Everything is Ok") {
    Write-Host "Extracting was successful elapsed $elapsedSec" -ForegroundColor DarkGreen
  }
  else {
    Write-Error "Extracting failed. Error Info: '$_result'"
  }
}

function New-TemporaryDirectory {
  $parent = [System.IO.Path]::GetTempPath()
  [string] $name = [System.Guid]::NewGuid()
  New-Item -ItemType Directory -Path (Join-Path $parent $name)
}


function RoboCopySourcetoDestination (
  [string] $sourceFolder,
  [string] $targetFolder ) {
  Write-Host "Prepare done elapsed $elapsedSec. Start copying to Destination Folder $targetFolder " -ForegroundColor DarkGreen
  $_v = @("$sourceFolder", "$targetFolder", "/mir", "/mt128", "/ndl", "/nfl", "/njh", "/np", "/LOG:robo.log")
  $_rc = Start-Process -FilePath robocopy -ArgumentList $_v -WindowStyle Hidden -PassThru -Wait
  $elapsedSec = "$(($Time.Elapsed).TotalSeconds) sec"
  $Time = $null
  if ($_rc.exitcode -lt 8) {
    Switch ($_rc.exitcode) {
      0 { $rbmsg = "$($_rc.exitcode): No files were copied." }
      1 { $rbmsg = "$($_rc.exitcode): All files were copied successfully." }
      2 { $rbmsg = "$($_rc.exitcode): No files were copied. Additional files in the destination directory." }
      3 { $rbmsg = "$($_rc.exitcode): Some files were copied." }
      default { $rbmsg = $($_rc.exitcode) }
    }
    Write-Host "Extracting was successful elapsed $elapsedSec, Robocopy retcode: '$rbmsg'" -ForegroundColor DarkGreen
  }
  else {
    #Write-host "Extracting was successful elapsed $elapsedSec" -ForegroundColor DarkGreen
    Write-Error "Extracting failed elapsed $elapsedSec", $_rc.expired
  }
}


function ExtractDocumentation (
  [string] $zipFile,
  [string] $outFolder,
  [string] $mirrorfolder, # subfolder of zipfile extraction , i.e. "system"
  [string] $zipexe,
  $zipOptions, # must be an string array
  [bool] $showCmd = $false ) {

  $Time = [System.Diagnostics.Stopwatch]::StartNew()
  $tempfolder = New-TemporaryDirectory
  Write-Host "Extracting: $zipFile to $outFolder via Tempfolder $tempfolder" -ForegroundColor Gray

  if ($showCmd -eq $true) {
    Write-Host $zipexe -p x -r -y -aoa -o"$tempfolder" $zipOptions $zipFile -ForegroundColor Gray
  }
  $_result = &$zipexe -p "x" -mmt100 -r -y -aoa -o"$tempfolder" $zipOptions $zipFile | Out-String
  $elapsedSec = "$(($Time.Elapsed).TotalSeconds) sec"

  Write-Host "Prepare done elapsed $elapsedSec. Start copying to Destination Folder $outFolder " -ForegroundColor DarkGreen
  $_v = @("$tempfolder", "$outFolder", "/s", "/e", "/mt128", "/ndl", "/nfl", "/njh", "/np", "/LOG:robo.log")
  $_rc = Start-Process -FilePath robocopy -ArgumentList $_v -WindowStyle Hidden -PassThru -Wait
  $elapsedSec = "$(($Time.Elapsed).TotalSeconds) sec"
  $Time = $null
  if ($_rc.exitcode -lt 8) {
    Switch ($_rc.exitcode) {
      0 { $rbmsg = "$($_rc.exitcode): No files were copied." }
      1 { $rbmsg = "$($_rc.exitcode): All files were copied successfully." }
      2 { $rbmsg = "$($_rc.exitcode): No files were copied. Additional files in the destination directory. " }
      3 { $rbmsg = "$($_rc.exitcode): Some files were copied." }
      default { $rbmsg = $($_rc.exitcode) }
    }
    Write-Host "Extracting was successful elapsed $elapsedSec, Robocopy retcode: '$rbmsg'" -ForegroundColor DarkGreen
  }
  else {
    #Write-host "Extracting was successful elapsed $elapsedSec" -ForegroundColor DarkGreen
    Write-Error "Extracting failed  elapsed $elapsedSec", $_rc.expired
  }

  # rei@13.10.2020: master copy process is done, now cleanup target folder from garbage of previous installations
  if ($mirrorfolder) {

    $mirrorItems = $mirrorfolder.split(',')
    foreach ($mirrorItem in $mirrorItems) {

      $Time = [System.Diagnostics.Stopwatch]::StartNew()
      Write-Host "Mirrorfolder for cleaning old file from target $mirrorItem" -ForegroundColor DarkGreen
      $mirfldr = Join-Path $tempfolder $mirrorItem
      $outmirrorTarget = Join-Path $outFolder $mirrorItem
      $_v = @("$mirfldr", "$outmirrorTarget", "/mir", "/mt128", "/ndl", "/nfl", "/njh", "/np", "/LOG:robo.log")
      $_rc = Start-Process -FilePath robocopy -ArgumentList $_v -WindowStyle Hidden -PassThru -Wait
      $elapsedSec = "$(($Time.Elapsed).TotalSeconds) sec"
      $Time = $null
      if ($_rc.exitcode -lt 8) {
        Switch ($_rc.exitcode) {
          0 { $rbmsg = "$($_rc.exitcode): No files were copied." }
          1 { $rbmsg = "$($_rc.exitcode): All files were copied successfully." }
          2 { $rbmsg = "$($_rc.exitcode): No files were copied. Additional files in the destination directory." }
          3 { $rbmsg = "$($_rc.exitcode): Some files were copied." }
          default { $rbmsg = $($_rc.exitcode) }
        }
        Write-Host "Mirorring $mirfldr was successful elapsed $elapsedSec, Robocopy retcode: '$rbmsg'" -ForegroundColor DarkGreen
      }
      else {
        Write-Error "Mirorring $mirfldr failed  elapsed $elapsedSec", $_rc.expired
      }
    }
  }
  # clean up temporary folder
  if (Test-Path $tempfolder) {
    Remove-Item -Path $tempfolder -Recurse -Force
  }
}

function ExtractandRoboCopyFile (
  [string] $zipFile,
  [string] $outFolder,
  [string] $zipexe,
  $zipOptions, # must be an string array
  [bool] $showCmd = $false ) {


  $Time = [System.Diagnostics.Stopwatch]::StartNew()
  $tempfolder = New-TemporaryDirectory
  Write-Host "Extracting: $zipFile to $outFolder via Tempfolder $tempfolder" -ForegroundColor Gray

  if ($showCmd -eq $true) {
    Write-Host $zipexe -p x -r -y -aoa -o"$tempfolder" $zipOptions $zipFile -ForegroundColor Gray
  }
  $_result = &$zipexe -p "x" -mmt100 -r -y -aoa -o"$tempfolder" $zipOptions $zipFile | Out-String
  $elapsedSec = "$(($Time.Elapsed).TotalSeconds) sec"

  Write-Host "Prepare done elapsed $elapsedSec. Start copying to Destination Folder $outFolder " -ForegroundColor DarkGreen
  $_v = @("$tempfolder", "$outFolder", "/s", "/e", "/mt128", "/ndl", "/nfl", "/njh", "/np", "/LOG:robo.log")
  $_rc = Start-Process -FilePath robocopy -ArgumentList $_v -WindowStyle Hidden -PassThru -Wait
  $elapsedSec = "$(($Time.Elapsed).TotalSeconds) sec"
  $Time = $null
  if ($_rc.exitcode -lt 8) {
    Switch ($_rc.exitcode) {
      0 { $rbmsg = "$($_rc.exitcode): No files were copied." }
      1 { $rbmsg = "$($_rc.exitcode): All files were copied successfully." }
      2 { $rbmsg = "$($_rc.exitcode): No files were copied. Additional files in the destination directory." }
      3 { $rbmsg = "$($_rc.exitcode): Some files were copied." }
      default { $rbmsg = $($_rc.exitcode) }
    }
    Write-Host "Extracting was successful elapsed $elapsedSec, Robocopy retcode: '$rbmsg'" -ForegroundColor DarkGreen
  }
  else {
    #Write-host "Extracting was successful elapsed $elapsedSec" -ForegroundColor DarkGreen
    Write-Error "Extracting failed  elapsed $elapsedSec", $_rc.expired
  }
  # clean up temporary folder
  if (Test-Path $tempfolder) {
    Remove-Item -Path $tempfolder -Recurse -Force
  }
}

function SetAppKeyValueIfFound {
  param(
    $appSettings,
    [string] $appkey,
    [string] $appNewValue
  )
  $_keyValue = $appSettings | Where-Object { $_.key -eq $appkey }
  if ($_keyValue) { $_keyValue.value = $appNewValue }
}

##############################
# This method
# adds a value into the web.config appsetting node
#.PARAMETER appRoot
#.PARAMETER appSettings
#.PARAMETER appkey
#.PARAMETER appNewValue
# SetAppKeyValue -appRoot $root.appSettings -appSettings $apps -appkey "scheduler:enabled" -appNewValue @(if ($schedulerEnabled){"true"} else {"false"})
##############################
function SetAppKeyValue (
  $appRoot,
  $appSettings,
  [string] $appkey,
  [string] $appNewValue
) {
  $_keyValue = $appSettings | Where-Object { $_.key -eq $appkey }
  if ($_keyValue) { $_keyValue.value = $appNewValue }
  else {
    $as = $xml.CreateElement("add")
    $as.SetAttribute("key", $appkey)
    $as.SetAttribute("value", $appNewValue)
    $_res = $appRoot.AppendChild($as)
  }
}

function RemoveAppKeyValue (
  $appRoot,
  $appSettings,
  [string] $appkey
) {
  $_keyValue = $appSettings | Where-Object { $_.key -eq $appkey }
  if ($_keyValue) {
    $appRoot.RemoveChild($_keyValue)
  }
}

#################################
# This function check in registry if require Core modul is install
# this module is required since 2.1 and might not be installed if prerequisite not reinstalled
# rei@28.8.18
function CheckCorsInstalled() {

  $_corsInstalled = Get-ItemProperty -Path "HKLM:SOFTWARE\Microsoft\IIS Extensions\CORS" -Name "Install" -ErrorAction ignore
  if ($_corsInstalled.install -ne 1) {
    Write-Host "Microsoft IIS Cors Module not installed. This module is required since 2.1.1." -ForegroundColor red
    Write-Host "Please ReRun Prerequisite script 01.1-itwo40-Install-iis-additionals.ps1 to solve this issue." -ForegroundColor red
    return $false
  }
  Write-Host "Cors Module found. Prerequisites ok."
  return $true
}

function KillProcessByCommandLinePattern {
  param (
    $pattern = $null,
    $withwait = $true)

  #Write-Host "KillProcessByCommandLinePattern check Process with pattern='$pattern'" -ForegroundColor $colorHeader
  #Get-WmiObject win32_process | Where-Object { $_.commandline -like "*$pattern*" } | Select-Object processid, name, commandline

  $private:f = Get-WmiObject win32_process | Where-Object { $_.commandline -like "*$pattern*" } | Select-Object processid, name, commandline
  if ($private:f -and $private:f.processid) {
    Write-Host "Running Process kill Id: '$($private:f.processid)' Name: '$($private:f.name)' pattern was '$pattern'"
    Stop-Process -Force $private:f.processid
    if ($withwait) {
      Start-Sleep 5   # sleep a while to make sure process ended...
    }
  }
}

function ShutdownService {
  param (
    $servicename,
    $pattern = $null,
    $withKill = $false)

  $_service = Get-Service -Name $servicename -ErrorAction SilentlyContinue
  if ($null -ne $_service) {
    Write-Host "Service '$servicename' exists >> we Stop it ..."
    if ($_service.Status -ne "Stopped") {
      Stop-Service -Name $servicename
      Start-Sleep 5   # sleep a while to make sure process ended...
    }
    if ($withKill) {
      if (-not $pattern) { $pattern = $servicename }
      KillProcessByCommandLinePattern -pattern $pattern
    }
  }
  else {
    Write-Host "No Service '$servicename' found"
  }
}

function RemoveService {
  param ($servicename, $withKill = $false)

  $_service = Get-Service -Name $servicename -ErrorAction SilentlyContinue
  if ($null -ne $_service) {
    Write-Host "Service '$servicename' exists >> we Stop it ..."
    if ($_service.Status -ne "Stopped") {
      Stop-Service -Name $servicename
      Start-Sleep 5   # sleep a while to make sure process ended...
      if ($withKill) {
        KillProcessByCommandLinePattern -pattern $servicename
      }
    }
    #Remove-Service -Name $servicename
    $_res = sc.exe delete $servicename
    Write-Host "Service '$servicename' removed "
  }
  else {
    Write-Host "No Service '$servicename' found"
  }
}

function RemoveVirtualDirectory ($vdirname, $websiteroot, $websitepath, $silent = $false) {
  ##############################################################################
  $vdirname1 = $websitepath + "/$vdirname"
  $path = "IIS:\Sites\$sitename\$vdirname"
  if (-not $silent) { Write-Host "Check existence VirtualDirectory '$vdirname1' on $websiteroot" -ForegroundColor $colorinfoLow }
  $f = Get-WebVirtualDirectory -Site $websiteroot -Name $vdirname1
  if ($f) {
    Write-Host "Remove WebVirtualDirectory $path" -ForegroundColor $colorinfo
    $result = Remove-Item $path -Force -Recurse
  }
}

function RemovePortalStartFolder ( $portalfolder, $clientRoot) {
  $clientFolder = $clientRoot
  $portalstart = Join-Path $portalfolder "start"
  if (Test-Path $portalstart) {
    Write-Host "Targetfolder for portal/start exists, delete it." -yellow
    $_res = Remove-Item -Path $portalstart -Force -Recurse
    return
  }
}

function CreatePortalStartFolder ( $portalfolder, $clientRoot) {
  $clientFolder = $clientRoot
  $portalstart = Join-Path $portalfolder "start"
  if (Test-Path $portalstart) {
    Write-Host "Targetfolder for portal/start already exists, cannot create." -red
    return
  }
  $_res = New-Item $portalstart -ItemType Junction -Value $clientFolder
}

