function Test-StateLock {
    <#
    .SYNOPSIS
        Checks for Terraform state locks and optionally force-unlocks
    
    .DESCRIPTION
        Checks if the Terraform state is locked in Lynx backend.
        Can automatically force-unlock if FORCE_UNLOCK environment variable is set to "true".
    
    .EXAMPLE
        Test-StateLock
    
    .EXAMPLE
        $env:FORCE_UNLOCK = "true"
        Test-StateLock
    
    .NOTES
        Environment Variables:
        - FORCE_UNLOCK: Set to "true" to automatically unlock locked states
        
        WARNING: Force unlocking can cause state corruption if another
        operation is legitimately running. Use with caution.
    #>
    
    Write-Host "--- Checking for state locks"
    
    $lockOutput = tofu force-unlock -list 2>&1
    
    if ($lockOutput -match "Lock Info") {
        Write-Host "⚠️  State is locked!"
        Write-Host $lockOutput
        
        if ($env:FORCE_UNLOCK -eq "true") {
            Write-Host "FORCE_UNLOCK enabled - attempting to unlock..."
            
            # Extract lock ID from output
            if ($lockOutput -match "ID:\s+(.+)") {
                $lockId = $matches[1].Trim()
                Write-Host "Unlocking with ID: $lockId"
                tofu force-unlock -force $lockId
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✓ State unlocked successfully"
                } else {
                    throw "Failed to force unlock state"
                }
            } else {
                throw "Could not extract lock ID from output"
            }
        } else {
            throw "State is locked. Set FORCE_UNLOCK=true to override, or wait for lock to clear."
        }
    } else {
        Write-Host "✓ No state locks detected"
    }
}
