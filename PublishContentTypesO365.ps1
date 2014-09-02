Add-Type -Path "$pwd\lib\microsoft.sharepoint.client.dll"
Add-Type -Path "$pwd\lib\microsoft.sharepoint.client.runtime.dll"

Function AuthenticateToO365($site, $username, $password) {

    if($site -eq $null)
    {
        $site = Read-Host "Please enter site name"
    }

    if($username -eq $null)
    {
        $username = Read-Host "Please enter username"
    }

    if($password -eq $null)
    {
        $password = Read-Host "Please enter password"
    }

    $securepassword = ConvertTo-SecureString  $password -AsPlainText -Force 

	write-Host "Logging on as $username..." -ForegroundColor Yellow

	$ctx = New-Object Microsoft.SharePoint.Client.ClientContext($site)
	$creds = New-Object  Microsoft.SharePoint.Client.SharePointOnlineCredentials($username, $securepassword)
	$ctx.Credentials = $creds 

	if(!$ctx.ServerObjectIsNull.Value)
	{
		write-host "Connected to O365!!"	
		return $ctx
	}    
}



Function PublishContentType($ctx, $contentTypeID, $operation) {
    $site = $ctx.Site
	$ctx.Load($site)
	$ctx.ExecuteQuery()

    $ctPubPageUrl = $site.Url + "/_layouts/15/managectpublishing.aspx?ctype=$contentTypeID"

	$cookieContainer = New-Object System.Net.CookieContainer
    
	$request = $ctx.WebRequestExecutorFactory.CreateWebRequestExecutor($ctx, $ctPubPageUrl).WebRequest
	
	if ($ctx.Credentials -ne $null)
	{
		$authCookieValue = $ctx.Credentials.GetAuthenticationCookie($ctx.Url)
	    # Create fed auth Cookie
	  	$fedAuth = new-object System.Net.Cookie
		$fedAuth.Name = "FedAuth"
	  	$fedAuth.Value = $authCookieValue.TrimStart("SPOIDCRL=")
	  	$fedAuth.Path = "/"
	  	$fedAuth.Secure = $true
	  	$fedAuth.HttpOnly = $true
	  	$fedAuth.Domain = (New-Object System.Uri($ctx.Url)).Host
	  	
		# Hookup authentication cookie to request
		$cookieContainer.Add($fedAuth)
		
		$request.CookieContainer = $cookieContainer
	}
	else
	{
		# No specific authentication required
		$request.UseDefaultCredentials = $true
	}
	
	$request.ContentLength = 0
	
	$response = $request.GetResponse()
	
	# decode response
	$strResponse = $null
	$stream = $response.GetResponseStream()
	if (-not([String]::IsNullOrEmpty($response.Headers["Content-Encoding"])))
	{
        if ($response.Headers["Content-Encoding"].ToLower().Contains("gzip"))
		{
            $stream = New-Object System.IO.Compression.GZipStream($stream, [System.IO.Compression.CompressionMode]::Decompress)
		}
		elseif ($response.Headers["Content-Encoding"].ToLower().Contains("deflate"))
		{
            $stream = new-Object System.IO.Compression.DeflateStream($stream, [System.IO.Compression.CompressionMode]::Decompress)
		}
	}
		
	# get response string
    $sr = New-Object System.IO.StreamReader($stream)

	$strResponse = $sr.ReadToEnd()
            
	$sr.Close()
	$sr.Dispose()
        
    $stream.Close()
		
    $inputMatches = $strResponse | Select-String -AllMatches -Pattern "<input.+?\/??>" | select -Expand Matches
		
    $inputs = @{}
		
    # Look for inputs and add them to the dictionary for postback values
    foreach ($match in $inputMatches)
    {

	    if (-not($match[0] -imatch "name=\""(.+?)\"""))
	    {
		    continue
	    }
	    $name = $matches[1]
			
	    if(-not($match[0] -imatch "value=\""(.+?)\"""))
	    {
		    continue
	    }
	    $value = $matches[1]

        #if it's the operation radion button group and it matches the action
        if($name -eq "ctl00`$PlaceHolderMain`$actionSection`$RadioGroupAction" -and $operation -eq $value)
        {
            $inputs.Add($name, $value)
        }
        #if it's the operation radion button group and it doesn't match the action
        elseif($name -eq "ctl00`$PlaceHolderMain`$actionSection`$RadioGroupAction" -and $operation -ne $value)
        {
            #do nothing
        }
        #otherwise, add the value
        else
        {
            $inputs.Add($name, $value)
        }

    } 
    
    # Format inputs as postback data string, but ignore the one that ends with iidIOGoBack
    $strPost = ""
    foreach ($inputKey in $inputs.Keys)
	{
        if (-not([String]::IsNullOrEmpty($inputKey)) -and -not($inputKey.EndsWith("iidIOGoBack")))
		{
            $strPost += [System.Uri]::EscapeDataString($inputKey) + "=" + [System.Uri]::EscapeDataString($inputs[$inputKey]) + "&"
		}
	}
	$strPost = $strPost.TrimEnd("&")
	
    $postData = [System.Text.Encoding]::UTF8.GetBytes($strPost);

    # Build postback request
    $publishRequest = $ctx.WebRequestExecutorFactory.CreateWebRequestExecutor($ctx, $ctPubPageUrl).WebRequest
    $publishRequest.Method = "POST"
    $publishRequest.Accept = "text/html, application/xhtml+xml, */*"
    if ($ctx.Credentials -ne $null)
	{
		$publishRequest.CookieContainer = $cookieContainer
	}
	else
	{
		# No specific authentication required
		$publishRequest.UseDefaultCredentials = $true
	}
    $publishRequest.ContentType = "application/x-www-form-urlencoded"
    $publishRequest.ContentLength = $postData.Length
    $publishRequest.UserAgent = "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)";
    $publishRequest.Headers["Cache-Control"] = "no-cache";
    $publishRequest.Headers["Accept-Encoding"] = "gzip, deflate";
    $publishRequest.Headers["Accept-Language"] = "fr-FR,en-US";

    # Add postback data to the request stream
    $stream = $publishRequest.GetRequestStream()
    $stream.Write($postData, 0, $postData.Length)
    $stream.Close();
	$stream.Dispose()
	
    # Perform the postback
    $response = $publishRequest.GetResponse()
	$response.Close()
	$response.Dispose()    
	
}

#
$ctx = AuthenticateToO365 $null $null $null

$web = $ctx.Web
$ctx.Load($web)
$ctx.ExecuteQuery()

$contenttypes = $web.AvailableContentTypes
$ctx.Load($contenttypes)
$ctx.ExecuteQuery()

foreach($ct in $contenttypes)
{
    if($ct.Group -eq "Custom Content Types")
    {
        PublishContentType $ctx "0x0100CA3A419E8543423C8EADAA70A97D8E47" "republishButton"
        write-host $ct.Name
    }    
}
		

#PublishContentType $ctx "0x0100CA3A419E8543423C8EADAA70A97D8E47" "unpublishButton"
#PublishContentType $ctx "0x0100CA3A419E8543423C8EADAA70A97D8E47" "publishButton"
