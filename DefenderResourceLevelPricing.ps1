# login to Azure
$azLogin = Get-AzContext

if ($null -eq $azLogin) {
    Write-Host "No login information found." -ForegroundColor Red
    # Login to Azure
    Connect-AzAccount
    $azLogin = Get-AzContext
    $account = $azLogin.Account
    Write-Host "Login with $account" -ForegroundColor Green
} else {
    $account = $azLogin.Account
    Write-Host "Login with $account" -ForegroundColor Green
}

# Get access token
$accesstoken = (Get-AzAccessToken).Token

# Create header for API
$headers = @{
    "Authorization" = "Bearer $accesstoken"
    "Content-Type" = "application/json"
}

# Define functions to set plans
function Set-Plan-P1 {
    param(
        [string]$vmId
    )
    $priceApiUrl = "https://management.azure.com$($vmId)/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"

    try {
        $body = @{
            properties = @{
                pricingTier = "Standard"
                subPlan = "P1"
            }
        }
        $bodyJson = $body | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Method Put -Uri $priceApiUrl -Headers $headers -Body $bodyJson
        Write-Host "Set Plan P1"
    } catch {
        Write-Host "Failed to execute API" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

function Set-Plan-Free {
    param(
        [string]$vmId
    )
    $priceApiUrl = "https://management.azure.com$($vmId)/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"

    try {
        $body = @{
            properties = @{
                pricingTier = "Free"
            }
        }
        $bodyJson = $body | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Method Put -Uri $priceApiUrl -Headers $headers -Body $bodyJson
        Write-Host "Set Plan Free"
    } catch {
        Write-Host "Failed to execute API" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

function Remove-Plan {
    param(
        [string]$vmId
    )
    $priceApiUrl = "https://management.azure.com$($vmId)/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"

    try {
        Invoke-RestMethod -Method DELETE -Uri $priceApiUrl -Headers $headers
        Write-Host "Remove Plan."
    } catch {
        Write-Host "Failed to execute API" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

function Get-MDEExtensions {
    param(
        [array]$extentions
    )

    $mdeExtensions = ""

    foreach ($extention in $extentions) {
        # Choose the last segment of the extension ID
        $lastSegment = ($extention.id -split "/")[-1]

        # if the last segment is "MDE.Windows" or "MDE.Linux", set it to $mdeExtensions
        if ($lastSegment -eq "MDE.Windows" -or $lastSegment -eq "MDE.Linux") {
            $mdeExtensions = $lastSegment
        }
    }
    return $mdeExtensions
}


# Get subscription List
$subsctiptionUrl = "https://management.azure.com/subscriptions?api-version=2022-12-01"
$SubscriptionIdLists = @()
try {
    $response = Invoke-RestMethod -Method Get -Uri $subsctiptionUrl -Headers $headers
    $response.value | ForEach-Object {
        $SubscriptionIdLists += $_.subscriptionId
    }
} catch {
    Write-Host "Failed to execute API" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit
}

# Debug
# $SubscriptionIdLists | Format-Table -AutoSize

$apiUrlLists = @()
foreach ($subscriptionId in $SubscriptionIdLists) {
    # Get VM List
    $apiUrlLists += "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Compute/virtualMachines?api-version=2023-03-01"
    $apiUrlLists += "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.HybridCompute/machines?api-version=2024-07-10"
    $apiUrlLists += "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Compute/virtualMachineScaleSets?api-version=2023-03-01"
}

$vmList = @()

foreach ($apiUrl in $apiUrlLists) {
    # Debug
    # Write-Host "Get VM List from $apiUrl" -ForegroundColor Green

    try {
        $response = Invoke-RestMethod -Method Get -Uri $apiUrl -Headers $headers
        
        $response.value | ForEach-Object {
            $resourceGroup = ($_."id" -split "/")[4]
            $subscriptionId = ($_."id" -split "/")[2]

            if($_.type -eq "Microsoft.Compute/virtualMachines") {
                $result = Get-MDEExtensions -extentions $_.resources
                $vmList += [PSCustomObject]@{
                    Id       = $_.id
                    SubscriptionId = $subscriptionId
                    Name     = $_.name
                    ResourceGroup = $resourceGroup
                    Type     = $_.type
                    TypeName = "VM"
                    Region   = $_.location
                    VmSize     = $_.properties.hardwareProfile.vmSize
                    OSType   = $_.properties.storageProfile.osDisk.osType
                    OS       = $_.properties.storageProfile.imageReference.offer
                    SKU      = $_.properties.storageProfile.imageReference.sku
                    Licence  = $_.properties.licenseType
                    Status   = $_.properties.provisioningState
                    MDE     = $result
                }
            } elseif ($_.type -eq "Microsoft.HybridCompute/machines") {
                $vmList += [PSCustomObject]@{
                    Id       = $_.id
                    SubscriptionId = $subscriptionId
                    Name     = $_.name
                    ResourceGroup = $resourceGroup
                    Type     = $_.type
                    TypeName = "Arc"
                    Region   = $_.location
                    VmSize   = ""
                    OSType   = $_.properties.osType
                    OS       = $_.properties.osName
                    SKU      = $_.properties.osSku
                    Licence  = ""
                    Status   = $_.properties.status
                }
            } elseif ($_.type -eq "Microsoft.Compute/virtualMachineScaleSets") {
                $vmList += [PSCustomObject]@{
                    Id       = $_.id
                    SubscriptionId = $subscriptionId
                    Name     = $_.name
                    ResourceGroup = $resourceGroup
                    Type     = $_.type
                    TypeName = "VMSS"
                    Region   = $_.location
                    VmSize     = $_.sku.name
                    OSType   = $_.properties.virtualMachineProfile.storageProfile.osDisk.osType
                    OS       = $_.properties.virtualMachineProfile.storageProfile.imageReference.offer
                    SKU      = $_.properties.virtualMachineProfile.storageProfile.imageReference.sku
                    Licence  = ""
                    Status   = ""
                }
            }
        }
    } catch {
        Write-Host "Failed to execute API" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        # if error occurs, exit the script
        exit
    }
}

# Debug
# $vmList | Select-Object SubscriptionId, Name, ResourceGroup, Type,TypeName, Region, VmSize, OSType, OS, SKU, Licence, Status, MDE | Format-Table -AutoSize

# Get Defender for Server Plan 
Write-Host "Plan Lists (Befor)" -ForegroundColor Blue

$priceList = $vmList | ForEach-Object {
    $difienderPriceUrl = "https://management.azure.com$($_.Id)/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
    try {
        $response = Invoke-RestMethod -Method Get -Uri $difienderPriceUrl -Headers $headers
        [PSCustomObject]@{
            Id       = $_.Id
            SubscriptionId = $_.SubscriptionId
            Name     = $_.Name
            ResourceGroup = $_.ResourceGroup
            Type     = $_.Type
            TypeName = $_.TypeName
            Region   = $_.Region
            VmSize     = $_.VmSize
            OSType   = $_.OSType
            OS       = $_.OS
            SKU      = $_.SKU
            Licence  = $_.Licence
            Status   = $_.Status
            PricingTier  = $response.properties.pricingTier
            SubPlan  = $response.properties.subPlan
            MDE     = $_.MDE
        }
    }
    catch {
        Write-Host "Failed to execute API" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        # if error occurs, exit the script
        exit
    }
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$priceList | Out-File -FilePath "$timestamp-befor-vmlist.txt" -Encoding utf8
$priceList | Select-Object Name, TypeName, Region, VmSize, OSType, OS, SKU, PricingTier, SubPlan, MDE | Format-Table -AutoSize

# Set Plan for Defender for Server
foreach ($vm in $priceList) {
    # Display the VM information
    $vm | Select-Object Name,TypeName, Region, VmSize, OSType,SKU, PricingTier, SubPlan |Format-Table -AutoSize

    # Input Defender for Server Plan by user
    $plan = Read-Host "Select Plan（1:P1 2:Free 3:Default 4:No change) Default is 4 "

    switch ($plan) {
        "1" {
            if($vm.TypeName -eq "VMSS") {
                Write-Host "VMSS cannot be set to P1." -ForegroundColor Red
            } else {
                Write-Host "Defender for Server 'P1' has been selected" -ForegroundColor Blue
                Set-Plan-P1 -vmId $vm.Id
            }
        }
        "2" {
            Write-Host "Defender for Server 'Free' has been selected" -ForegroundColor Blue
            Set-Plan-Free -vmId $vm.Id
        }
        "3" {
            Write-Host "Default has been selected" -ForegroundColor Blue
            Remove-Plan -vmId $vm.Id
        }
        Default {
            Write-Host "No changes."
        }
    }
}

# Get Defender for Server Plan 
Write-Host "Plan Lists (After)" -ForegroundColor Blue

$priceList = $vmList | ForEach-Object {
    $difienderPriceUrl = "https://management.azure.com$($_.Id)/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
    try {
        $response = Invoke-RestMethod -Method Get -Uri $difienderPriceUrl -Headers $headers
        [PSCustomObject]@{
            Id       = $_.Id
            SubscriptionId = $_.SubscriptionId
            Name     = $_.Name
            ResourceGroup = $_.ResourceGroup
            Type     = $_.Type
            TypeName = $_.TypeName
            Region   = $_.Region
            VmSize     = $_.VmSize
            OSType   = $_.OSType
            OS       = $_.OS
            SKU      = $_.SKU
            Licence  = $_.Licence
            Status   = $_.Status
            PricingTier  = $response.properties.pricingTier
            SubPlan  = $response.properties.subPlan
            MDE     = $_.MDE
        }
    }
    catch {
        Write-Host "Failed to execute API" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        # if error occurs, exit the script
        exit
    }
}

$priceList | Out-File -FilePath "$timestamp-after-vmlist.txt" -Encoding utf8
$priceList | Select-Object Name, TypeName, Region, VmSize, OSType, OS, SKU, PricingTier, SubPlan, MDE | Format-Table -AutoSize