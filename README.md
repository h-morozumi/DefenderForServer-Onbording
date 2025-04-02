# DefenderForServer-Onbording
How to separate plans by resource in Defender for Servers?

## 概要
Microsoft Defender for Cloud で、リソース単位でプランを設定する検証を行う。

※現在、Arc未対応

リソース単位でプランを設定することで、特定のリソースに対してのみ Defender for Cloud の機能を有効化することができる。
これにより、コストを抑えつつ、必要なセキュリティ機能を適用することが可能になる。

### 注意事項

Defender for Servers Plan 1 と Plan 2 では、リソース単位での有効化（無効化）の挙動が異なるため、注意が必要です。

- リソース単位での有効化（無効化）は、API経由でのみ設定が可能
- Defender for Servers Plan 1 の場合は、リソース単位で有効化・無効化が可能
- Defender for Servers Plan 1 の場合は、サブスクリプションで有効化している際のリソース個別の無効化と、サブスクリプションで無効化している場合の個別の有効化の両方が可能
- Defender for Servers Plan 2 の場合は、リソース単位で無効化のみ可能（有効化は不可）
- Defender for Servers Plan 2 の場合は、サブスクリプションで有効化した後にリソース個別の無効化のみ可能 (リソース個別の有効化は不可)
- Plan 1 と Plan 2 を混在させたい場合、まずはサブスクリプションで Plan 2 を有効化し、その後にリソース単位で Plan 1 を有効化、又は 無効化する必要があります。
- リソース個別で無効化する場合、すでに MDE オンボーディング済みであれば、個別にオフボーディングが必要
- 新規 VM をリソース個別で無効化したい場合は、MDE オンボーディング用の拡張機能がデプロイされるまでに無効化する必要がある


## REST API での検証

まずは、Azure CLI を使用して、リソース単位でのプランを設定するための REST API を呼び出す方法を確認します。

- Azure CLI を使用してAzure にログインする

```powershell
Connect-AzAccount -Tenant <tenant_id>
```

- Azure CLI を使用して、アクセストークンを取得する
```powershell
 (Get-AzAccessToken).Token
```

- .env.example から .env を作成し、変数を設定してください
- .env の中の変数を設定してください
  - AZURE_ACCESS_TOKEN に、上記で取得したアクセストークンを設定してください
  - AZURE_SUBSCRIPTION_ID に、Azure のサブスクリプション ID を設定してください
  - AZURE_RESOURCE_GROUP_NAME に、リソースグループ名を設定してください
  - AZURE_VM_NAME に、VM 名を設定してください
- VSCode に REST Client 拡張機能をインストールしてください
- defender-for-server-api.http を開いて、「Send Request」をクリックして実行します

## PowerShell での検証

VM毎に Defender for Cloud のプランを設定するための PowerShell スクリプトを作成しました。

このスクリプトを使用することで、特定の VM に対して Defender for Cloud のプランを設定することができます。

```powershell
./defender-pricing.ps1
```

```
Name          ResourceGroup   Region        Size            OSType  OS         Licence        Status    PricingTier SubPlan
----          -------------   ------        ----            ------  --         -------        ------    ----------- -------
test-win-vm   EX-TESTVM       japaneast     Standard_D2s_v4 Windows windows-11 Windows_Client Succeeded Standard    P1
vmware-player EX-VMWAREPLAYER japanwest     Standard_D4s_v5 Windows windows-11 Windows_Client Succeeded Free
ses-0         RS-AVD-DEMO     canadacentral Standard_D2s_v4 Windows windows-11 Windows_Client Succeeded Standard    P2
```

## 参考

- [Microsoft Defender for Cloud で Defender for Servers をデプロイする - Microsoft Defender for Cloud | Microsoft Learn](https://learn.microsoft.com/ja-jp/azure/defender-for-cloud/tutorial-enable-servers-plan#enable-defender-for-servers-at-the-resource-level) 
- [Defender for Servers でリソース単位でプラン](https://qiita.com/YoshiakiOi/items/35c3b8e339421c217aa2)
- [Microsoft-Defender-for-Cloud/Powershell scripts/Defender for Servers on resource level at main · Azure/Microsoft-Defender-for-Cloud](https://github.com/Azure/Microsoft-Defender-for-Cloud/tree/main/Powershell%20scripts/Defender%20for%20Servers%20on%20resource%20level) 

## メモ(後で修正するためのメモ)

現在の環境にARC環境がないため、後日検証し修正する

拡張機能の確認

```powershell
Get-AzVMExtension -ResourceGroupName "YourResourceGroupName" -VMName "YourVMName" -Name "MDE.Windows"
```

追加方法(未検証)

```powershell
Set-AzVMExtension -ResourceGroupName "YourResourceGroupName" -VMName "YourVMName" -Name "MDE.Windows" -Publisher "Microsoft.Azure.AzureDefenderForServers" -ExtensionType "MDE.Windows" -TypeHandlerVersion "1.0"
```

削除方法（未検証）

```powershell
Remove-AzVMExtension -ResourceGroupName "YourResourceGroupName" -VMName "YourVMName" -Name "MDE.Windows"
```

