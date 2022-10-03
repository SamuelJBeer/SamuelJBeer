param (
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string] $Path,

    [ValidateNotNullOrEmpty()]
    [string[]] $Collection,

    [ValidateNotNullOrEmpty()]
    [Hashtable] $DefaultValues = @{},

    [ValidateNotNullOrEmpty()]
    [ValidateSet('HTML', 'Markdown', 'String')]
    [String] $OutputFormat = 'Markdown',

    [Switch] $ShowHeading
)

$OutputFormatStrings = @{
    HTML     = @{ Header = '<h2>{0}</h2>'; Badge = '<img alt="{0}" src="{1}"/>' }
    Markdown = @{ Header = "## {0}`n---"; Badge = '![{0}]({1})' }
    String   = @{ Header = '{0}'; Badge = '{0} = {1}' }
}

function ToCamelCase([string] $String) {
    return $String -replace '^([A-Z])', { $_.Groups[1].Value.ToLower() }
}

function Write-ValueChanged ($Key, $Value) {
    $str = "[BADGE] Value of '${Key}' changed to '${Value}'."
    Write-Debug $str
}

function Format-GithubBadge {
    param (
        [Parameter(Mandatory, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        $InputObject
    )

    Process {
        try {
            $uriRequest = [System.UriBuilder]::new('https://img.shields.io/static/v1')
            $uriQuery = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
            $labelStr = $InputObject.Label

            # Set DefaultValues as defined within the JSON file
            foreach ($default in $DefaultValues.Keys) {
                if ($InputObject.Keys -inotcontains $default) {
                    $InputObject.$default = $DefaultValues.$default
                    Write-ValueChanged $default $InputObject.$default
                }
            }

            # Generate logo string from label string
            if ($InputObject.Keys -inotcontains 'Logo') {
                $InputObject.Logo = $InputObject.Label.ToLower().Replace(' ', '-')
                Write-ValueChanged 'Logo' $InputObject.Logo
            }

            # Set value of message to label if message is undefined
            if ($InputObject.Keys -inotcontains 'Message') {
                $InputObject.Message = $labelStr
                Write-ValueChanged 'Message' $InputObject.Message
            }

            # Remove redundant value if label and message match
            if ($InputObject.Label -eq $InputObject.Message) { 
                $InputObject.Label = $null
                Write-ValueChanged 'Label' $InputObject.Label
            }

            # Generate query string from InputObject
            foreach ($key in $InputObject.Keys) {
                $uriQuery.Set((ToCamelCase($key)), $InputObject.$key)
            }

            $uriRequest.Query = $uriQuery.ToString()

            $OutputFormatStrings.$OutputFormat.Badge -f $labelStr, $uriRequest.Uri.ToString()
        } catch {
            $_
        }
    }
}

function Format-GithubBadgeCollection {
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('HTML', 'Markdown', 'String')]
        [String] $OutputFormat,

        [switch] $ShowHeading
    )

    Process {
        try {
            Write-Debug ('[COLLECTION] Title: {0}, Badges: {1}):' -f $_.Title, $_.Badges.Count)

            if ($ShowHeading) {
                if (-not $_.Title) {
                    throw [System.Text.Json.JsonException]'Collection missing required key "Title".'
                }

                $OutputFormatStrings.$OutputFormat.Header -f $_.Title
            }

            $_.Badges | Sort-Object -Property { $_.Label } | Format-GithubBadge

            ''
        } catch {
            $_
        }
    }
}

try {
    Write-Verbose ('Attempting to parse JSON file: {0}' -f $Path)
    $jsonData = (Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable)

    if (-not $jsonData.ContainsKey('Collections')) {
        throw [System.Text.Json.JsonException]::new('JSON file missing required key: "Collections".')
    }

    if ($jsonData.ContainsKey('Defaults')) {
        $jsonData.Defaults.GetEnumerator() | ForEach-Object {
            if (-not $DefaultValues.ContainsKey($_.Key)) {
                $DefaultValues[$_.Key] = $_.Value
                Write-Debug ('Set {0} default value: {1}' -f $_.Key, $DefaultValues[$_.Key])
            }
        }
    } else {
        Write-Debug 'No Defaults configured in JSON File'
    }

    $collectionData = $jsonData.Collections | Sort-Object -Property { [int] $_.Order }

    if ($Collection) {
        $collectionData = $collectionData | Where-Object -Property Title -In $Collection
    }

    if (-not $collectionData) {
        throw [System.Text.Json.JsonException]::new('No Collection data matching search parameters defined.')
    }

    $collectionData | Format-GithubBadgeCollection -OutputFormat $OutputFormat -ShowHeading:$ShowHeading
} catch {
    $_
}
