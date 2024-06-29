. "$PSScriptRoot\..\Private\ConvertTo-UnixTimestamp.ps1"
. "$PSScriptRoot\Invoke-ServiceDeskApi.ps1"

# TODO: Add parameter set for setting a status when scheduling a resume time (Message unused otherwise)

function Suspend-ServiceDeskRequest {
    param (
        # Id of the request to suspend
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Int64]
        $Id,

        # Date and time to resume the request
        [datetime]
        $Until,

        # Message describing why the request is suspended
        $Message
    )

    begin {
        $Data = @{
            request = @{
                status = @{
                    name = 'Onhold'
                }
            }
        }

        if ($Until) {
            $Data.request.onhold_scheduler = @{
                change_to_status = @{
                    name = 'Open'
                }

                scheduled_time = @{
                    value = ConvertTo-UnixTimestamp $Until
                }
            }

            if ($Message) {
                $Data.request.onhold_scheduler.comments = $Message
            }
        }
    }

    process {
        foreach ($RequestId in $Id) {
            # Build the request parameters
            $InvokeParams = @{
                Method = 'Put'
                Operation = 'Update'
                Id = $RequestId
                Data = $Data
            }

            # Make the API request
            $Response = Invoke-RestMethod @InvokeParams

            $Response
        }
    }
}
