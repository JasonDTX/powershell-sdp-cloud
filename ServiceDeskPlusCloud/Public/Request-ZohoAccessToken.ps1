function Request-ZohoAccessToken {
    [CmdletBinding(DefaultParameterSetName = 'FromParams')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'FromParams')]
        $GrantToken,

        [Parameter(ParameterSetName = 'FromParams')]
        $ClientId,

        [Parameter(ParameterSetName = 'FromParams')]
        $ClientSecret,

        [Parameter(Mandatory, ParameterSetName = 'FromFile')]
        $FilePath
    )

    # Retrieve secrets
    $SecretParams = @{
        AsPlainText = $true
        Vault = 'Zoho'
    }

    if (!$PSBoundParameters.ContainsKey('ClientId')) {
        $ClientId = Get-Secret @SecretParams -Name 'CLIENT_ID'
    }

    if (!$PSBoundParameters.ContainsKey('ClientSecret')) {
        $ClientSecret = Get-Secret @SecretParams -Name 'CLIENT_SECRET'
    }

    switch ($PSCmdlet.ParameterSetName) {
        'FromParams' {
            $Body = @{
                code = $GrantToken
                grant_type = 'authorization_code'
                client_id = $ClientId
                client_secret = $ClientSecret
            }
        }

        'FromFile' {
            $FileContent = Get-Content -Raw -Path $FilePath | ConvertFrom-Json

            $Body = @{
                code = $FileContent.code
                grant_type = $FileContent.grant_type
                client_id = $FileContent.client_id
                client_secret = $FileContent.client_secret
            }
        }
    }

    # Record next expiration time
    $script:ZohoAccessExpirationTime = (Get-Date).AddHours(1)

    # Execute request
    $RestMethodParameters = @{
        Uri = 'https://accounts.zoho.com/oauth/v2/token'
        Method = 'Post'
        Body = $Body
    }

    Invoke-RestMethod @RestMethodParameters
}
