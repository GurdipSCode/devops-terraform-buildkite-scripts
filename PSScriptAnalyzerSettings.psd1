# PSScriptAnalyzerSettings.psd1
# PowerShell Script Analyzer configuration
# https://github.com/PowerShell/PSScriptAnalyzer

@{
    # Severity levels to include
    Severity = @(
        'Error',
        'Warning',
        'Information'
    )

    # Rules to include
    IncludeRules = @(
        # Security rules
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSAvoidUsingUsernameAndPasswordParams',
        'PSAvoidUsingInvokeExpression',
        'PSUsePSCredentialType',
        
        # Best practices
        'PSAvoidUsingCmdletAliases',
        'PSAvoidUsingPositionalParameters',
        'PSAvoidGlobalVars',
        'PSAvoidUsingEmptyCatchBlock',
        'PSAvoidUsingWriteHost',
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUseCmdletCorrectly',
        'PSUseApprovedVerbs',
        'PSUseSingularNouns',
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseOutputTypeCorrectly',
        
        # Code style
        'PSPlaceOpenBrace',
        'PSPlaceCloseBrace',
        'PSUseConsistentIndentation',
        'PSUseConsistentWhitespace',
        'PSAlignAssignmentStatement',
        
        # Maintainability
        'PSAvoidLongLines',
        'PSAvoidUsingDoubleQuotesForConstantString',
        'PSUseLiteralInitializerForHashtable',
        
        # Documentation
        'PSProvideCommentHelp',
        
        # Performance
        'PSAvoidUsingWMICmdlet',
        'PSUseSupportsShouldProcess'
    )

    # Rules to exclude
    ExcludeRules = @(
        # Allow Write-Host for CI/CD console output
        # Comment this out if you want strict enforcement
        # 'PSAvoidUsingWriteHost'
    )

    # Rule configurations
    Rules = @{
        # Brace placement - same line
        PSPlaceOpenBrace = @{
            Enable = $true
            OnSameLine = $true
            NewLineAfter = $true
            IgnoreOneLineBlock = $true
        }

        PSPlaceCloseBrace = @{
            Enable = $true
            NewLineAfter = $false
            IgnoreOneLineBlock = $true
            NoEmptyLineBefore = $false
        }

        # Indentation - 4 spaces
        PSUseConsistentIndentation = @{
            Enable = $true
            Kind = 'space'
            PipelineIndentation = 'IncreaseIndentationForFirstPipeline'
            IndentationSize = 4
        }

        # Whitespace
        PSUseConsistentWhitespace = @{
            Enable = $true
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckPipeForRedundantWhitespace = $false
            CheckSeparator = $true
            CheckParameter = $false
            IgnoreAssignmentOperatorInsideHashTable = $true
        }

        # Line length
        PSAvoidLongLines = @{
            Enable = $true
            MaximumLineLength = 120
        }

        # Alignment
        PSAlignAssignmentStatement = @{
            Enable = $true
            CheckHashtable = $true
        }

        # Comment-based help
        PSProvideCommentHelp = @{
            Enable = $true
            ExportedOnly = $false
            BlockComment = $true
            VSCodeSnippetCorrection = $false
            Placement = 'begin'
        }

        # Approved verbs - allow some common variations
        PSUseApprovedVerbs = @{
            Enable = $true
        }

        # Cmdlet aliases to avoid
        PSAvoidUsingCmdletAliases = @{
            Enable = $true
            AllowList = @()  # No aliases allowed
        }
    }
}
