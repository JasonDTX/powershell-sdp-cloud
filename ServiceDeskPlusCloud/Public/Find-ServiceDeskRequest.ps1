. "$PSScriptRoot\..\private\Format-ZohoHeader.ps1"
. "$PSScriptRoot\..\private\Format-ZohoSearch.ps1"

<#
.SYNOPSIS
    Find a ServiceDesk Plus request based on specified criteria.

.PARAMETER Portal
    The portal for the ServiceDesk Plus Cloud instance.

.PARAMETER Status
    Request status to filter results by.

.PARAMETER Technician
    Request technician to filter results by.

.PARAMETER Fields
    Request fields to include in results.

.EXAMPLE
    Find-ServiceDeskRequest -Portal portalname -Technician foo.bar@example.com
    Return requests owned by the specified technician.
#>

function Find-ServiceDeskRequest {
    param (
        [Parameter(Mandatory)]
        $Portal,

        [ValidateNotNull()]
        [string[]]
        $Status = 'Open',

        [ValidateNotNull()]
        $Technician,

        [string[]]
        $Fields
    )

    # Build search object from PSBoundParameters to avoid a parade of
    # statements like `if ($PSBoundParameters.ContainsKey("Foo")) { ... }`
    $SearchParams = $PSBoundParameters
    $SearchParams.Remove('Portal')

    # Build input data object
    $Data = @{
        list_info = @{
            row_count = 100
            start_index = 1
            get_total_count = $true
            search_criteria = Format-ZohoSearch @SearchParams
        }
    }

    # Limit response object to specific fields
    if ($PSBoundParameters.ContainsKey('Fields')) {
        $Data.list_info.fields_required = $Fields
    }

    $Body = @{
        input_data = ($Data | ConvertTo-Json -Depth 4 -Compress)
    }

    # Send the request
    $RestMethodParameters = @{
        Uri = "https://sdpondemand.manageengine.com/app/$Portal/api/v3/requests"
        Headers = Format-ZohoHeader
        Method = 'Get'
        Body = $Body
    }

    $Response = Invoke-RestMethod @RestMethodParameters

    # Handle the response

    # Format the response object
    foreach ($Request in $Response.requests) {
        [pscustomobject] [ordered] @{
            Requester = $Request.requester.email_id
            Template = $Request.template.name
            CreatedTime = $Request.created_time.display_value
            HasDraft = $Request.has_draft
            CancelledComments = $Request.cancel_flag_comments
            DisplayId = $Request.display_id
            Subject = $Request.subject
            Technician = $Request.technician.email_id
            DueTime = $Request.due_by_time.display_value
            IsServiceRequest = $Request.is_service_request
            Cancelled = $Request.cancellation_requested
            HasNotes = $Request.has_notes
            Id = $Request.id
            Maintenance = $Request.maintenance
            Status = $Request.status.name
            Group = $Request.group.name
        } | select $Fields
    }
}
