function Get-ImperionVoyageEmbedding {
    <#
    .SYNOPSIS
        Embed text with Voyage AI `voyage-3-large` at the pinned 1024 dimension (ADR-0009).
    .DESCRIPTION
        Connect-layer wrapper for the Voyage embeddings REST API — the system's ONLY
        embedding provider (front-end ADR-0041; backend ADR-0034 uses the same model for
        query embeddings). Batches inputs to the API limit, sends `input_type` (use
        'document' when embedding corpus text — the backend embeds queries with 'query'),
        pins `output_dimension` to the contract, and REFUSES any response vector that is
        not exactly the pinned dimension so vector spaces can never silently mix.

        Key resolution (front-end ADR-0129 §8, supersedes ADR-0009's local-secret order):
        explicit -ApiKey wins; else the Voyage key is the platform-scope AI credential read
        from Key Vault by the cert SP at the canonical registry name
        `EmbeddingProviderKeyVaultSecret` (default `conn-platform-voyage`). The mis-named
        starter secret (`Voyage-Embedding-API-Key` / SecretStore `embedding-provider-key`)
        is retired — there is no SecretStore mirror for this key any more (it is custodied
        through the `connection` registry's `platform` scope, the same authoritative
        KV link the backend resolves; folds #389).
        Throttling/backoff is handled by Invoke-ImperionRestWithRetry (429/503 +
        Retry-After). Returns per-input vectors in input order plus the billed token
        total for cost telemetry.
    .PARAMETER Text
        One or more texts to embed (document chunks or a query).
    .PARAMETER InputType
        'document' (corpus text — the default here) or 'query' (search queries).
    .PARAMETER ApiKey
        Voyage API key. Defaults to the Key Vault platform secret named by
        EmbeddingProviderKeyVaultSecret (`conn-platform-voyage`, ADR-0129 §8).
    .OUTPUTS
        [pscustomobject] @{ Embeddings = [float[][]]; TotalTokens = [int]; Model = [string] }
        — Embeddings[i] corresponds to Text[i].
    .EXAMPLE
        $result = Get-ImperionVoyageEmbedding -Text $chunks -InputType document
        $result.Embeddings[0].Length   # 1024
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string[]] $Text,
        [ValidateSet('document', 'query')][string] $InputType = 'document',
        [string] $ApiKey
    )

    $contract = Get-ImperionVectorContract
    if (-not $ApiKey) {
        # Platform-scope AI credential (ADR-0129 §8): the Voyage key is custodied in the
        # `connection` registry's platform scope at the canonical KV name conn-platform-voyage,
        # read directly by the cert SP. No SecretStore mirror (the mis-named starter secret is
        # retired).
        $secretNames = Get-ImperionSecretNames
        $keyVaultSecretName =
            if ($secretNames -is [System.Collections.IDictionary] -and $secretNames.Contains('EmbeddingProviderKeyVaultSecret')) {
                $secretNames['EmbeddingProviderKeyVaultSecret']
            }
            else { 'conn-platform-voyage' }
        $ApiKey = Get-ImperionKeyVaultSecret -Name $keyVaultSecretName
    }

    $headers = @{ Authorization = "Bearer $ApiKey"; Accept = 'application/json' }
    $allEmbeddings = [System.Collections.Generic.List[object]]::new()
    $totalTokens = 0

    for ($offset = 0; $offset -lt $Text.Count; $offset += $contract.ApiBatchSize) {
        $batchEnd = [math]::Min($offset + $contract.ApiBatchSize, $Text.Count) - 1
        $batch = @($Text[$offset..$batchEnd])

        $body = @{
            model            = $contract.EmbeddingModel
            input            = $batch
            input_type       = $InputType
            output_dimension = $contract.Dimension
        } | ConvertTo-Json -Depth 4

        $response = Invoke-ImperionRestWithRetry -Uri $contract.ApiBaseUri -Headers $headers -Method POST -Body $body

        # Voyage returns { data: [{ index, embedding }], usage: { total_tokens } } —
        # re-order by index defensively and enforce the pinned dimension on every vector.
        $batchData = @($response.Body.data | Sort-Object -Property index)
        if ($batchData.Count -ne $batch.Count) {
            throw "Voyage returned $($batchData.Count) embeddings for a batch of $($batch.Count) inputs."
        }
        foreach ($item in $batchData) {
            $vector = @($item.embedding)
            if ($vector.Count -ne $contract.Dimension) {
                throw "Voyage returned a $($vector.Count)-dim vector; the pinned contract is $($contract.Dimension) (front-end ADR-0041). Refusing to mix vector spaces."
            }
            $allEmbeddings.Add($vector)
        }
        $usage = Get-ImperionPropertyPath -InputObject $response.Body -Path 'usage.total_tokens'
        if ($usage) { $totalTokens += [int]$usage }
    }

    [pscustomobject]@{
        Embeddings  = $allEmbeddings.ToArray()
        TotalTokens = $totalTokens
        Model       = $contract.EmbeddingModel
    }
}
