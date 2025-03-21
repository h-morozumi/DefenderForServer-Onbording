# Azureにログインしているか確認
$azLogin = Get-AzContext

if ($null -eq $azLogin) {
    Write-Host "Azureにログインしていません。"
    # Azureにログイン
    Connect-AzAccount
    $azLogin = Get-AzContext
    $account = $azLogin.Account
    Write-Host "$account でログインしました。"
} else {
    $account = $azLogin.Account
    Write-Host "$account でログインしています。"
}

# Azureのサブスクリプション情報を取得
$subscriptionId = $azLogin.Subscription.Id # 取得したいサブスクリプションIDを指定

# Accessトークンを取得
$accesstoken = Get-AzAccessToken
$token = $accesstoken.Token

# REST API に渡すHeaderを作成
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

# Defender のプランを設定する関数を定義
function Set-Plan-P1 {
    param(
        [string]$vmName,
        [string]$resourceGroupName
    )
    $priceApiUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
    # API を実行
    try {
        $body = @{
            properties = @{
                pricingTier = "Standard"
                subPlan = "P1"
            }
        }
        $bodyJson = $body | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Method Put -Uri $priceApiUrl -Headers $headers -Body $bodyJson
        Write-Host "$vmName の Defender for Server を【P1】に設定しました。"
    } catch {
        Write-Host "APIの実行に失敗しました。"
        Write-Host $_.Exception.Message
    }
}

function Set-Plan-Free {
    param(
        [string]$vmName,
        [string]$resourceGroupName
    )
    $priceApiUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
    # API を実行
    try {
        $body = @{
            properties = @{
                pricingTier = "Free"
            }
        }
        $bodyJson = $body | ConvertTo-Json -Depth 10
        Invoke-RestMethod -Method Put -Uri $priceApiUrl -Headers $headers -Body $bodyJson
        Write-Host "$vmName の Defender for Server を【Free】に設定しました。"
    } catch {
        Write-Host "APIの実行に失敗しました。"
        Write-Host $_.Exception.Message
    }
}

function Remove-Plan {
    param(
        [string]$vmName,
        [string]$resourceGroupName
    )
    $priceApiUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
    # API を実行
    try {
        Invoke-RestMethod -Method DELETE -Uri $priceApiUrl -Headers $headers
        Write-Host "$vmName の Defender for Server を【Subscriptionからの継承】に設定しました。"
    } catch {
        Write-Host "APIの実行に失敗しました。"
        Write-Host $_.Exception.Message
    }
}


# 仮想マシン一覧の API URL
$vmUrl = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Compute/virtualMachines?api-version=2023-03-01"

# API を実行
try {
    $vmList = Invoke-RestMethod -Method Get -Uri $vmUrl -Headers $headers

    $vmData = $vmList.value | ForEach-Object {
        $resourceGroup = ($_."id" -split "/")[4]
        [PSCustomObject]@{
            Name     = $_.name
            ResourceGroup = $resourceGroup
            Region   = $_.location
            Size     = $_.properties.hardwareProfile.vmSize
            OSType   = $_.properties.storageProfile.osDisk.osType
            OS       = $_.properties.storageProfile.imageReference.offer
            Licence  = $_.properties.licenseType
            Status   = $_.properties.provisioningState
        }
    }
    # $vmData | Format-Table -AutoSize
    # $vmData | Out-File -FilePath "vmList.txt" -Encoding utf8
    # Write-Output "------- JSON -----------------------"
    # $vmJson = $vmList | ConvertTo-Json -Depth 10
    # Write-Output $vmJson

} catch {
    Write-Host "APIの実行に失敗しました。"
    Write-Host $_.Exception.Message
    exit
}

# resourceGroupとvmNameを指定してDefender for Serverのプラン情報を取得
Write-Host "Plan Lists（Befor）" -ForegroundColor Red
$priceList = $vmData | ForEach-Object {
    $resourceGroupName = $_.ResourceGroup
    $vmName = $_.Name
    $defenderPriceUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
    # API を実行
    try {
        $response = Invoke-RestMethod -Method Get -Uri $defenderPriceUrl -Headers $headers
        # Write-Output "------- JSON -----------------------"
        # $vmJson = $response | ConvertTo-Json -Depth 10
        # Write-Output $vmJson
        [PSCustomObject]@{
            Name     = $_.name
            ResourceGroup = $resourceGroupName
            Region   = $_.Region
            Size     = $_.Size
            OSType   = $_.OSType
            OS       = $_.OS
            Licence  = $_.Licence
            Status   = $_.Status
            PricingTier     = $response.properties.pricingTier
            SubPlan  = $response.properties.subPlan
        }
    } catch {
        Write-Host "APIの実行に失敗しました。"
        Write-Host $_.Exception.Message
        exit
    }
}
$priceList | Format-Table -AutoSize

$priceList | ForEach-Object {
    # データを表示
    $_ | Format-Table -AutoSize

    # NameとResourceGroupを取得
    $vmName = $_.Name
    $resourceGroupName = $_.ResourceGroup

    # 設定したいプランを選択
    $plan = Read-Host "プランを選択してください（1:P1 2:Free 3:Subscription 4:変更なし）"
    switch ($plan) {
        "1" { 
            Write-Host "P1が選択されました。"
            Set-Plan-P1 -vmName $vmName -resourceGroupName $resourceGroupName
        }
        "2" {
            Write-Host "Freeが選択されました。"
            Set-Plan-Free -vmName $vmName -resourceGroupName $resourceGroupName
        }
        "3" {
            Write-Host "Subscriptionが選択されました。"
            Remove-Plan -vmName $vmName -resourceGroupName $resourceGroupName
        }
        Default {
            Write-Host "変更しません"
        }
    }
}

# resourceGroupとvmNameを指定してDefender for Serverのプラン情報を取得
Write-Host "Plan Lists（After）" -ForegroundColor Red
$priceList = $vmData | ForEach-Object {
    $resourceGroupName = $_.ResourceGroup
    $vmName = $_.Name
    $defenderPriceUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Compute/virtualMachines/$vmName/providers/Microsoft.Security/pricings/VirtualMachines?api-version=2024-01-01"
    # API を実行
    try {
        $response = Invoke-RestMethod -Method Get -Uri $defenderPriceUrl -Headers $headers
        # Write-Output "------- JSON -----------------------"
        # $vmJson = $response | ConvertTo-Json -Depth 10
        # Write-Output $vmJson
        [PSCustomObject]@{
            Name     = $_.name
            ResourceGroup = $resourceGroupName
            Region   = $_.Region
            Size     = $_.Size
            OSType   = $_.OSType
            OS       = $_.OS
            Licence  = $_.Licence
            Status   = $_.Status
            PricingTier     = $response.properties.pricingTier
            SubPlan  = $response.properties.subPlan
        }
    } catch {
        Write-Host "APIの実行に失敗しました。"
        Write-Host $_.Exception.Message
        exit
    }
}
$priceList | Format-Table -AutoSize
