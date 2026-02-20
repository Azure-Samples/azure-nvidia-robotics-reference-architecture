#Requires -Modules Pester
# Copyright (c) Microsoft Corporation.
# SPDX-License-Identifier: MIT

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '../../lib/Modules/CIHelpers.psm1'
    Import-Module $modulePath -Force

    $mockPath = Join-Path $PSScriptRoot '../Mocks/GitMocks.psm1'
    Import-Module $mockPath -Force
}

#region ConvertTo-GitHubActionsEscaped Tests

Describe 'ConvertTo-GitHubActionsEscaped' {
    Context 'Basic escaping' {
        It 'Escapes percent character' {
            $result = ConvertTo-GitHubActionsEscaped -Value 'test%value'
            $result | Should -Be 'test%25value'
        }

        It 'Escapes carriage return' {
            $result = ConvertTo-GitHubActionsEscaped -Value "test`rvalue"
            $result | Should -Be 'test%0Dvalue'
        }

        It 'Escapes newline' {
            $result = ConvertTo-GitHubActionsEscaped -Value "test`nvalue"
            $result | Should -Be 'test%0Avalue'
        }

        It 'Escapes double colon' {
            $result = ConvertTo-GitHubActionsEscaped -Value 'test::value'
            $result | Should -Be 'test%3A%3Avalue'
        }

        It 'Escapes multiple special characters' {
            $result = ConvertTo-GitHubActionsEscaped -Value "test%::value`n"
            $result | Should -Be 'test%25%3A%3Avalue%0A'
        }
    }

    Context 'ForProperty flag' {
        It 'Escapes colon when ForProperty is specified' {
            $result = ConvertTo-GitHubActionsEscaped -Value 'test:value' -ForProperty
            $result | Should -Be 'test%3Avalue'
        }

        It 'Escapes comma when ForProperty is specified' {
            $result = ConvertTo-GitHubActionsEscaped -Value 'test,value' -ForProperty
            $result | Should -Be 'test%2Cvalue'
        }

        It 'Escapes colon and comma along with standard characters' {
            $result = ConvertTo-GitHubActionsEscaped -Value "test:%value,`n" -ForProperty
            $result | Should -Be 'test%3A%25value%2C%0A'
        }

        It 'Does not escape colon or comma without ForProperty' {
            $result = ConvertTo-GitHubActionsEscaped -Value 'test:value,end'
            $result | Should -Be 'test:value,end'
        }
    }

    Context 'Empty and null values' {
        It 'Returns empty string unchanged' {
            $result = ConvertTo-GitHubActionsEscaped -Value ''
            $result | Should -Be ''
        }

        It 'Returns empty string for null value' {
            $result = ConvertTo-GitHubActionsEscaped -Value $null
            $result | Should -Be ''
        }
    }

    Context 'Order of escape operations' {
        It 'Escapes percent first to avoid double-encoding' {
            $result = ConvertTo-GitHubActionsEscaped -Value '%0A'
            $result | Should -Be '%250A'
        }
    }
}

#endregion

#region ConvertTo-AzureDevOpsEscaped Tests

Describe 'ConvertTo-AzureDevOpsEscaped' {
    Context 'Basic escaping' {
        It 'Escapes percent character with AZP encoding' {
            $result = ConvertTo-AzureDevOpsEscaped -Value 'test%value'
            $result | Should -Be 'test%AZP25value'
        }

        It 'Escapes carriage return with AZP encoding' {
            $result = ConvertTo-AzureDevOpsEscaped -Value "test`rvalue"
            $result | Should -Be 'test%AZP0Dvalue'
        }

        It 'Escapes newline with AZP encoding' {
            $result = ConvertTo-AzureDevOpsEscaped -Value "test`nvalue"
            $result | Should -Be 'test%AZP0Avalue'
        }

        It 'Escapes opening bracket' {
            $result = ConvertTo-AzureDevOpsEscaped -Value 'test[value'
            $result | Should -Be 'test%AZP5Bvalue'
        }

        It 'Escapes closing bracket' {
            $result = ConvertTo-AzureDevOpsEscaped -Value 'test]value'
            $result | Should -Be 'test%AZP5Dvalue'
        }

        It 'Escapes multiple special characters' {
            $result = ConvertTo-AzureDevOpsEscaped -Value "test%[value]`n"
            $result | Should -Be 'test%AZP25%AZP5Bvalue%AZP5D%AZP0A'
        }
    }

    Context 'ForProperty flag' {
        It 'Escapes semicolon when ForProperty is specified' {
            $result = ConvertTo-AzureDevOpsEscaped -Value 'test;value' -ForProperty
            $result | Should -Be 'test%AZP3Bvalue'
        }

        It 'Escapes semicolon along with standard characters' {
            $result = ConvertTo-AzureDevOpsEscaped -Value "test;%value[`n" -ForProperty
            $result | Should -Be 'test%AZP3B%AZP25value%AZP5B%AZP0A'
        }

        It 'Does not escape semicolon without ForProperty' {
            $result = ConvertTo-AzureDevOpsEscaped -Value 'test;value'
            $result | Should -Be 'test;value'
        }
    }

    Context 'Empty and null values' {
        It 'Returns empty string unchanged' {
            $result = ConvertTo-AzureDevOpsEscaped -Value ''
            $result | Should -Be ''
        }

        It 'Returns empty string for null value' {
            $result = ConvertTo-AzureDevOpsEscaped -Value $null
            $result | Should -Be ''
        }
    }

    Context 'Order of escape operations' {
        It 'Escapes percent first to avoid double-encoding' {
            $result = ConvertTo-AzureDevOpsEscaped -Value '%AZP0A'
            $result | Should -Be '%AZP25AZP0A'
        }
    }
}

#endregion

#region Get-CIPlatform Tests

Describe 'Get-CIPlatform' {
    BeforeEach {
        Save-CIEnvironment
        Clear-MockCIEnvironment
    }

    AfterEach {
        Restore-CIEnvironment
    }

    Context 'GitHub Actions detection' {
        It 'Returns github when GITHUB_ACTIONS is true' {
            $env:GITHUB_ACTIONS = 'true'
            $result = Get-CIPlatform
            $result | Should -Be 'github'
        }

        It 'Prioritizes GitHub over Azure DevOps' {
            $env:GITHUB_ACTIONS = 'true'
            $env:TF_BUILD = 'True'
            $result = Get-CIPlatform
            $result | Should -Be 'github'
        }
    }

    Context 'Azure DevOps detection' {
        It 'Returns azdo when TF_BUILD is True' {
            $env:TF_BUILD = 'True'
            $result = Get-CIPlatform
            $result | Should -Be 'azdo'
        }

        It 'Returns azdo when AZURE_PIPELINES is True' {
            $env:AZURE_PIPELINES = 'True'
            $result = Get-CIPlatform
            $result | Should -Be 'azdo'
        }

        It 'Returns azdo when both TF_BUILD and AZURE_PIPELINES are set' {
            $env:TF_BUILD = 'True'
            $env:AZURE_PIPELINES = 'True'
            $result = Get-CIPlatform
            $result | Should -Be 'azdo'
        }
    }

    Context 'Local execution' {
        It 'Returns local when no CI variables are set' {
            $result = Get-CIPlatform
            $result | Should -Be 'local'
        }

        It 'Returns local when GITHUB_ACTIONS is not true' {
            $env:GITHUB_ACTIONS = 'false'
            $result = Get-CIPlatform
            $result | Should -Be 'local'
        }

        It 'Returns local when TF_BUILD is not True' {
            $env:TF_BUILD = 'False'
            $result = Get-CIPlatform
            $result | Should -Be 'local'
        }
    }
}

#endregion

#region Test-CIEnvironment Tests

Describe 'Test-CIEnvironment' {
    BeforeEach {
        Save-CIEnvironment
        Clear-MockCIEnvironment
    }

    AfterEach {
        Restore-CIEnvironment
    }

    Context 'CI environment detection' {
        It 'Returns true in GitHub Actions' {
            $env:GITHUB_ACTIONS = 'true'
            $result = Test-CIEnvironment
            $result | Should -BeTrue
        }

        It 'Returns true in Azure DevOps' {
            $env:TF_BUILD = 'True'
            $result = Test-CIEnvironment
            $result | Should -BeTrue
        }

        It 'Returns false in local execution' {
            $result = Test-CIEnvironment
            $result | Should -BeFalse
        }
    }
}

#endregion

#region Set-CIOutput Tests

Describe 'Set-CIOutput' {
    BeforeAll {
        $script:testOutputFile = Join-Path $TestDrive 'github-output.txt'
    }

    BeforeEach {
        Save-CIEnvironment
        Clear-MockCIEnvironment
        if (Test-Path $script:testOutputFile) {
            Remove-Item $script:testOutputFile -Force
        }
    }

    AfterEach {
        Restore-CIEnvironment
    }

    Context 'GitHub Actions platform' {
        BeforeEach {
            $env:GITHUB_ACTIONS = 'true'
            $env:GITHUB_OUTPUT = $script:testOutputFile
        }

        It 'Writes name=value to GITHUB_OUTPUT file' {
            Set-CIOutput -Name 'test-var' -Value 'test-value'
            $content = Get-Content -Path $script:testOutputFile -Raw
            $content | Should -BeLike '*test-var=test-value*'
        }

        It 'Escapes special characters in name' {
            Set-CIOutput -Name 'test:name' -Value 'value'
            $content = Get-Content -Path $script:testOutputFile -Raw
            $content | Should -BeLike '*test%3Aname=value*'
        }

        It 'Escapes special characters in value' {
            Set-CIOutput -Name 'name' -Value "value`nwith newline"
            $content = Get-Content -Path $script:testOutputFile -Raw
            $content | Should -BeLike '*name=value%0Awith newline*'
        }

        It 'Appends to existing file' {
            'existing content' | Out-File -FilePath $script:testOutputFile
            Set-CIOutput -Name 'var1' -Value 'val1'
            Set-CIOutput -Name 'var2' -Value 'val2'
            $content = Get-Content -Path $script:testOutputFile -Raw
            $content | Should -BeLike '*existing content*'
            $content | Should -BeLike '*var1=val1*'
            $content | Should -BeLike '*var2=val2*'
        }

        It 'Handles empty value' {
            Set-CIOutput -Name 'empty-var' -Value ''
            $content = Get-Content -Path $script:testOutputFile -Raw
            $content | Should -BeLike '*empty-var=*'
        }
    }

    Context 'Azure DevOps platform' {
        BeforeEach {
            $env:TF_BUILD = 'True'
            Mock Write-Host { } -ModuleName 'CIHelpers'
        }

        It 'Emits setvariable logging command' {
            Set-CIOutput -Name 'test-var' -Value 'test-value'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -match '##vso\[task\.setvariable variable=test-var.*test-value'
            }
        }

        It 'Escapes special characters in variable name' {
            Set-CIOutput -Name 'test;var' -Value 'value'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*variable=test%AZP3Bvar*'
            }
        }

        It 'Escapes special characters in value' {
            Set-CIOutput -Name 'var' -Value 'value[test]'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*value%AZP5Btest%AZP5D*'
            }
        }

        It 'Includes isOutput flag when IsOutput is specified' {
            Set-CIOutput -Name 'output-var' -Value 'value' -IsOutput
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*variable=output-var;isOutput=true*'
            }
        }

        It 'Does not include isOutput flag by default' {
            Set-CIOutput -Name 'regular-var' -Value 'value'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -notlike '*isOutput=true*'
            }
        }
    }

    Context 'Local platform' {
        BeforeEach {
            Mock Write-Verbose { } -ModuleName 'CIHelpers' -Verifiable
        }

        It 'Logs via Write-Verbose' {
            Set-CIOutput -Name 'local-var' -Value 'local-value'
            Should -Invoke -CommandName Write-Verbose -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*local-var=local-value*'
            }
        }
    }
}

#endregion

#region Set-CIEnv Tests

Describe 'Set-CIEnv' {
    BeforeAll {
        $script:testEnvFile = Join-Path $TestDrive 'github-env.txt'
    }

    BeforeEach {
        Save-CIEnvironment
        Clear-MockCIEnvironment
        if (Test-Path $script:testEnvFile) {
            Remove-Item $script:testEnvFile -Force
        }
    }

    AfterEach {
        Restore-CIEnvironment
    }

    Context 'GitHub Actions platform' {
        BeforeEach {
            $env:GITHUB_ACTIONS = 'true'
            $env:GITHUB_ENV = $script:testEnvFile
        }

        It 'Writes heredoc syntax to GITHUB_ENV file' {
            Set-CIEnv -Name 'TEST_VAR' -Value 'test-value'
            $content = Get-Content -Path $script:testEnvFile -Raw
            $content | Should -BeLike '*TEST_VAR<<EOF_*'
            $content | Should -BeLike '*test-value*'
        }

        It 'Handles multiline values' {
            Set-CIEnv -Name 'MULTILINE_VAR' -Value "line1`nline2`nline3"
            $content = Get-Content -Path $script:testEnvFile -Raw
            $content | Should -BeLike '*MULTILINE_VAR<<EOF_*'
            $content | Should -BeLike "*line1`nline2`nline3*"
        }

        It 'Uses unique delimiters for each variable' {
            Set-CIEnv -Name 'VAR1' -Value 'value1'
            Set-CIEnv -Name 'VAR2' -Value 'value2'
            $content = Get-Content -Path $script:testEnvFile
            $delimiters = $content | Where-Object { $_ -like 'EOF_*' }
            ($delimiters | Select-Object -Unique).Count | Should -Be 2
        }

        It 'Appends to existing file' {
            'existing content' | Out-File -FilePath $script:testEnvFile
            Set-CIEnv -Name 'VAR1' -Value 'val1'
            $content = Get-Content -Path $script:testEnvFile -Raw
            $content | Should -BeLike '*existing content*'
            $content | Should -BeLike '*VAR1<<EOF_*'
        }

        It 'Handles empty value' {
            Set-CIEnv -Name 'EMPTY_VAR' -Value ''
            $content = Get-Content -Path $script:testEnvFile -Raw
            $content | Should -BeLike '*EMPTY_VAR<<EOF_*'
        }
    }

    Context 'Azure DevOps platform' {
        BeforeEach {
            $env:TF_BUILD = 'True'
            Mock Write-Host { } -ModuleName 'CIHelpers'
        }

        It 'Emits setvariable logging command' {
            Set-CIEnv -Name 'TEST_VAR' -Value 'test-value'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -match '##vso\[task\.setvariable variable=TEST_VAR.*test-value'
            }
        }

        It 'Escapes special characters in variable name' {
            Set-CIEnv -Name 'TEST_VAR_NAME' -Value 'value'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*variable=TEST_VAR_NAME*'
            }
        }

        It 'Escapes special characters in value' {
            Set-CIEnv -Name 'VAR' -Value "value`nwith newline"
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*value%AZP0Awith newline*'
            }
        }
    }

    Context 'Local platform' {
        BeforeEach {
            Mock Write-Verbose { } -ModuleName 'CIHelpers' -Verifiable
        }

        It 'Logs via Write-Verbose' {
            Set-CIEnv -Name 'LOCAL_VAR' -Value 'local-value'
            Should -Invoke -CommandName Write-Verbose -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*LOCAL_VAR=local-value*'
            }
        }
    }

    Context 'Invalid variable names' {
        BeforeEach {
            Mock Write-Warning { } -ModuleName 'CIHelpers' -Verifiable
        }

        It 'Warns and returns for name starting with digit' {
            Set-CIEnv -Name '9VAR' -Value 'value'
            Should -Invoke -CommandName Write-Warning -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*Invalid environment variable name*'
            }
        }

        It 'Warns and returns for name with invalid characters' {
            Set-CIEnv -Name 'VAR-NAME' -Value 'value'
            Should -Invoke -CommandName Write-Warning -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*Invalid environment variable name*'
            }
        }

        It 'Warns and returns for name with spaces' {
            Set-CIEnv -Name 'VAR NAME' -Value 'value'
            Should -Invoke -CommandName Write-Warning -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*Invalid environment variable name*'
            }
        }

        It 'Accepts valid name with underscores' {
            Mock Write-Verbose { } -ModuleName 'CIHelpers'
            { Set-CIEnv -Name 'VALID_VAR_NAME' -Value 'value' } | Should -Not -Throw
        }

        It 'Accepts valid name starting with underscore' {
            Mock Write-Verbose { } -ModuleName 'CIHelpers'
            { Set-CIEnv -Name '_PRIVATE_VAR' -Value 'value' } | Should -Not -Throw
        }
    }
}

#endregion

#region Write-CIStepSummary Tests

Describe 'Write-CIStepSummary' {
    BeforeAll {
        $script:testSummaryFile = Join-Path $TestDrive 'step-summary.txt'
        $script:testMarkdownFile = Join-Path $TestDrive 'test-summary.md'
    }

    BeforeEach {
        Save-CIEnvironment
        Clear-MockCIEnvironment
        if (Test-Path $script:testSummaryFile) {
            Remove-Item $script:testSummaryFile -Force
        }
        if (Test-Path $script:testMarkdownFile) {
            Remove-Item $script:testMarkdownFile -Force
        }
    }

    AfterEach {
        Restore-CIEnvironment
    }

    Context 'GitHub Actions platform' {
        BeforeEach {
            $env:GITHUB_ACTIONS = 'true'
            $env:GITHUB_STEP_SUMMARY = $script:testSummaryFile
        }

        It 'Writes markdown content to GITHUB_STEP_SUMMARY file' {
            $markdown = "# Test Summary`n- Item 1`n- Item 2"
            Write-CIStepSummary -Content $markdown
            $content = Get-Content -Path $script:testSummaryFile -Raw
            $content | Should -BeLike '*# Test Summary*'
            $content | Should -BeLike '*- Item 1*'
        }

        It 'Appends to existing summary file' {
            '# Existing Summary' | Out-File -FilePath $script:testSummaryFile
            Write-CIStepSummary -Content '## New Section'
            $content = Get-Content -Path $script:testSummaryFile -Raw
            $content | Should -BeLike '*# Existing Summary*'
            $content | Should -BeLike '*## New Section*'
        }

        It 'Reads markdown from file when Path parameter is used' {
            '# File Summary' | Set-Content -Path $script:testMarkdownFile
            Write-CIStepSummary -Path $script:testMarkdownFile
            $content = Get-Content -Path $script:testSummaryFile -Raw
            $content | Should -BeLike '*# File Summary*'
        }

        It 'Warns and returns when Path file does not exist' {
            Mock Write-Warning { } -ModuleName 'CIHelpers' -Verifiable
            Write-CIStepSummary -Path 'TestDrive:/nonexistent.md'
            Should -Invoke -CommandName Write-Warning -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*not found*'
            }
            $script:testSummaryFile | Should -Not -Exist
        }
    }

    Context 'Azure DevOps platform' {
        BeforeEach {
            $env:TF_BUILD = 'True'
            Mock Write-Host { } -ModuleName 'CIHelpers'
        }

        It 'Emits section header and markdown content' {
            $markdown = "# Summary`n- Result: Pass"
            Write-CIStepSummary -Content $markdown
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -eq '##[section]Step Summary'
            }
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*# Summary*'
            }
        }

        It 'Escapes vso logging commands in content' {
            Write-CIStepSummary -Content 'Test ##vso[task.complete] in summary'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -match '`##vso\[task\.complete\]'
            }
        }

        It 'Escapes generic logging commands in content' {
            Write-CIStepSummary -Content 'Test ##[debug] in summary'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -match '`##\['
            }
        }

        It 'Reads markdown from file when Path parameter is used' {
            '# ADO Summary' | Set-Content -Path $script:testMarkdownFile
            Write-CIStepSummary -Path $script:testMarkdownFile
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*# ADO Summary*'
            }
        }
    }

    Context 'Local platform' {
        BeforeEach {
            Mock Write-Verbose { } -ModuleName 'CIHelpers' -Verifiable
        }

        It 'Logs via Write-Verbose' {
            Write-CIStepSummary -Content 'Local summary content'
            Should -Invoke -CommandName Write-Verbose -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*Local summary content*'
            }
        }
    }
}

#endregion

#region Write-CIAnnotation Tests

Describe 'Write-CIAnnotation' {
    BeforeEach {
        Save-CIEnvironment
        Clear-MockCIEnvironment
    }

    AfterEach {
        Restore-CIEnvironment
    }

    Context 'GitHub Actions platform' {
        BeforeEach {
            $env:GITHUB_ACTIONS = 'true'
            Mock Write-Host { } -ModuleName 'CIHelpers'
        }

        It 'Emits warning annotation' {
            Write-CIAnnotation -Message 'Test warning' -Level 'Warning'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '::warning::Test warning'
            }
        }

        It 'Emits error annotation' {
            Write-CIAnnotation -Message 'Test error' -Level 'Error'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '::error::Test error'
            }
        }

        It 'Emits notice annotation' {
            Write-CIAnnotation -Message 'Test notice' -Level 'Notice'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '::notice::Test notice'
            }
        }

        It 'Defaults to warning level' {
            Write-CIAnnotation -Message 'Default level'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '::warning::Default level'
            }
        }

        It 'Includes file property when specified' {
            Write-CIAnnotation -Message 'Error in file' -Level 'Error' -File 'scripts/test.ps1'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '::error file=scripts/test.ps1::Error in file'
            }
        }

        It 'Normalizes Windows backslashes to forward slashes in file path' {
            Write-CIAnnotation -Message 'Error' -Level 'Error' -File 'scripts\test\file.ps1'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*file=scripts/test/file.ps1*'
            }
        }

        It 'Includes line property when specified' {
            Write-CIAnnotation -Message 'Error' -Level 'Error' -File 'test.ps1' -Line 42
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*line=42*'
            }
        }

        It 'Includes column property when specified' {
            Write-CIAnnotation -Message 'Error' -Level 'Error' -File 'test.ps1' -Line 42 -Column 10
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*col=10*'
            }
        }

        It 'Combines file, line, and column properties' {
            Write-CIAnnotation -Message 'Syntax error' -Level 'Error' -File 'src/app.ps1' -Line 100 -Column 5
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '::error file=src/app.ps1,line=100,col=5::Syntax error'
            }
        }

        It 'Escapes special characters in message' {
            Write-CIAnnotation -Message "Error with`nnewline" -Level 'Error'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*Error with%0Anewline*'
            }
        }

        It 'Escapes special characters in file property' {
            Write-CIAnnotation -Message 'Error' -Level 'Error' -File 'path:with:colons.ps1'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*file=path%3Awith%3Acolons.ps1*'
            }
        }

        It 'Skips line and column when value is 0 or negative' {
            Write-CIAnnotation -Message 'Error' -Level 'Error' -File 'test.ps1' -Line 0 -Column -1
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -notlike '*line=*' -and $Object -notlike '*col=*'
            }
        }

        It 'Handles empty message' {
            Write-CIAnnotation -Message '' -Level 'Warning'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -eq '::warning::'
            }
        }
    }

    Context 'Azure DevOps platform' {
        BeforeEach {
            $env:TF_BUILD = 'True'
            Mock Write-Host { } -ModuleName 'CIHelpers'
        }

        It 'Emits warning logissue' {
            Write-CIAnnotation -Message 'Test warning' -Level 'Warning'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -match '##vso\[task\.logissue type=warning\].*Test warning'
            }
        }

        It 'Emits error logissue' {
            Write-CIAnnotation -Message 'Test error' -Level 'Error'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -match '##vso\[task\.logissue type=error\].*Test error'
            }
        }

        It 'Maps Notice to info type' {
            Write-CIAnnotation -Message 'Test notice' -Level 'Notice'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -match '##vso\[task\.logissue type=info\].*Test notice'
            }
        }

        It 'Includes sourcepath property when File is specified' {
            Write-CIAnnotation -Message 'Error' -Level 'Error' -File 'scripts/test.ps1'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*sourcepath=scripts/test.ps1*'
            }
        }

        It 'Normalizes Windows backslashes to forward slashes in sourcepath' {
            Write-CIAnnotation -Message 'Error' -Level 'Error' -File 'scripts\test\file.ps1'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*sourcepath=scripts/test/file.ps1*'
            }
        }

        It 'Includes linenumber property when Line is specified' {
            Write-CIAnnotation -Message 'Error' -Level 'Error' -File 'test.ps1' -Line 42
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*linenumber=42*'
            }
        }

        It 'Includes columnnumber property when Column is specified' {
            Write-CIAnnotation -Message 'Error' -Level 'Error' -File 'test.ps1' -Line 42 -Column 10
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*columnnumber=10*'
            }
        }

        It 'Combines all properties' {
            Write-CIAnnotation -Message 'Syntax error' -Level 'Error' -File 'src/app.ps1' -Line 100 -Column 5
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*type=error;sourcepath=src/app.ps1;linenumber=100;columnnumber=5*Syntax error*'
            }
        }

        It 'Escapes special characters in message' {
            Write-CIAnnotation -Message 'Error[test]' -Level 'Error'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*Error%AZP5Btest%AZP5D*'
            }
        }

        It 'Escapes special characters in sourcepath property' {
            Write-CIAnnotation -Message 'Error' -Level 'Error' -File 'path;with;semicolons.ps1'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*sourcepath=path%AZP3Bwith%AZP3Bsemicolons.ps1*'
            }
        }
    }

    Context 'Local platform' {
        BeforeEach {
            Mock Write-Warning { } -ModuleName 'CIHelpers' -Verifiable
        }

        It 'Logs warning via Write-Warning' {
            Write-CIAnnotation -Message 'Local warning' -Level 'Warning'
            Should -Invoke -CommandName Write-Warning -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*[Warning]*Local warning*'
            }
        }

        It 'Logs error via Write-Warning with Error prefix' {
            Write-CIAnnotation -Message 'Local error' -Level 'Error'
            Should -Invoke -CommandName Write-Warning -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*[Error]*Local error*'
            }
        }

        It 'Includes file location when specified' {
            Write-CIAnnotation -Message 'Error' -Level 'Error' -File 'test.ps1'
            Should -Invoke -CommandName Write-Warning -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*test.ps1*'
            }
        }

        It 'Includes line and column when specified' {
            Write-CIAnnotation -Message 'Error' -Level 'Error' -File 'test.ps1' -Line 42 -Column 10
            Should -Invoke -CommandName Write-Warning -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*test.ps1:42:10*'
            }
        }
    }
}

#endregion

#region Write-CIAnnotations Tests

Describe 'Write-CIAnnotations' {
    BeforeEach {
        Save-CIEnvironment
        $env:GITHUB_ACTIONS = 'true'
        Mock Write-Host { } -ModuleName 'CIHelpers'
    }

    AfterEach {
        Restore-CIEnvironment
    }

    Context 'PSScriptAnalyzer summary processing' {
        It 'Emits annotations for each issue in summary' {
            $summary = [PSCustomObject]@{
                Results = @(
                    [PSCustomObject]@{
                        Issues = @(
                            [PSCustomObject]@{
                                Message  = 'Error 1'
                                Severity = 'Error'
                                File     = 'file1.ps1'
                                Line     = 10
                                Column   = 5
                            },
                            [PSCustomObject]@{
                                Message  = 'Warning 1'
                                Severity = 'Warning'
                                File     = 'file2.ps1'
                                Line     = 20
                                Column   = 15
                            }
                        )
                    }
                )
            }

            Write-CIAnnotations -Summary $summary
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 2
        }

        It 'Maps Error severity to Error level' {
            $summary = [PSCustomObject]@{
                Results = @(
                    [PSCustomObject]@{
                        Issues = @(
                            [PSCustomObject]@{
                                Message  = 'Critical error'
                                Severity = 'Error'
                                File     = 'test.ps1'
                            }
                        )
                    }
                )
            }

            Write-CIAnnotations -Summary $summary
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '::error*'
            }
        }

        It 'Maps non-Error severities to Warning level' {
            $summary = [PSCustomObject]@{
                Results = @(
                    [PSCustomObject]@{
                        Issues = @(
                            [PSCustomObject]@{
                                Message  = 'Info issue'
                                Severity = 'Information'
                                File     = 'test.ps1'
                            }
                        )
                    }
                )
            }

            Write-CIAnnotations -Summary $summary
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '::warning*'
            }
        }

        It 'Skips issues with null or empty messages' {
            $summary = [PSCustomObject]@{
                Results = @(
                    [PSCustomObject]@{
                        Issues = @(
                            [PSCustomObject]@{
                                Message  = ''
                                Severity = 'Error'
                                File     = 'test.ps1'
                            },
                            [PSCustomObject]@{
                                Message  = $null
                                Severity = 'Warning'
                                File     = 'test.ps1'
                            },
                            [PSCustomObject]@{
                                Message  = '   '
                                Severity = 'Error'
                                File     = 'test.ps1'
                            }
                        )
                    }
                )
            }

            Write-CIAnnotations -Summary $summary
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 0
        }

        It 'Includes file, line, and column properties when available' {
            $summary = [PSCustomObject]@{
                Results = @(
                    [PSCustomObject]@{
                        Issues = @(
                            [PSCustomObject]@{
                                Message  = 'Full details'
                                Severity = 'Error'
                                File     = 'src/test.ps1'
                                Line     = 100
                                Column   = 25
                            }
                        )
                    }
                )
            }

            Write-CIAnnotations -Summary $summary
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*file=src/test.ps1*' -and
                $Object -like '*line=100*' -and
                $Object -like '*col=25*'
            }
        }

        It 'Handles multiple results with multiple issues' {
            $summary = [PSCustomObject]@{
                Results = @(
                    [PSCustomObject]@{
                        Issues = @(
                            [PSCustomObject]@{
                                Message  = 'Error 1'
                                Severity = 'Error'
                                File     = 'file1.ps1'
                            },
                            [PSCustomObject]@{
                                Message  = 'Error 2'
                                Severity = 'Error'
                                File     = 'file1.ps1'
                            }
                        )
                    },
                    [PSCustomObject]@{
                        Issues = @(
                            [PSCustomObject]@{
                                Message  = 'Warning 1'
                                Severity = 'Warning'
                                File     = 'file2.ps1'
                            }
                        )
                    }
                )
            }

            Write-CIAnnotations -Summary $summary
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 3
        }

        It 'Handles summary with no issues' {
            $summary = [PSCustomObject]@{
                Results = @(
                    [PSCustomObject]@{
                        Issues = @()
                    }
                )
            }

            Write-CIAnnotations -Summary $summary
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 0
        }

        It 'Handles summary with empty Results array' {
            $summary = [PSCustomObject]@{
                Results = @()
            }

            Write-CIAnnotations -Summary $summary
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 0
        }
    }
}

#endregion

#region Set-CITaskResult Tests

Describe 'Set-CITaskResult' {
    BeforeEach {
        Save-CIEnvironment
        Clear-MockCIEnvironment
    }

    AfterEach {
        Restore-CIEnvironment
    }

    Context 'GitHub Actions platform' {
        BeforeEach {
            $env:GITHUB_ACTIONS = 'true'
            Mock Write-Host { } -ModuleName 'CIHelpers'
            Mock Write-Verbose { } -ModuleName 'CIHelpers'
        }

        It 'Emits error annotation for Failed result' {
            Set-CITaskResult -Result 'Failed'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -eq '::error::Task failed'
            }
        }

        It 'Logs via Write-Verbose for Succeeded result' {
            Set-CITaskResult -Result 'Succeeded'
            Should -Invoke -CommandName Write-Verbose -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*Succeeded*'
            }
        }

        It 'Logs via Write-Verbose for SucceededWithIssues result' {
            Set-CITaskResult -Result 'SucceededWithIssues'
            Should -Invoke -CommandName Write-Verbose -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*SucceededWithIssues*'
            }
        }
    }

    Context 'Azure DevOps platform' {
        BeforeEach {
            $env:TF_BUILD = 'True'
            Mock Write-Host { } -ModuleName 'CIHelpers'
        }

        It 'Emits task.complete for Failed result' {
            Set-CITaskResult -Result 'Failed'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -eq '##vso[task.complete result=Failed]'
            }
        }

        It 'Emits task.complete for Succeeded result' {
            Set-CITaskResult -Result 'Succeeded'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -eq '##vso[task.complete result=Succeeded]'
            }
        }

        It 'Emits task.complete for SucceededWithIssues result' {
            Set-CITaskResult -Result 'SucceededWithIssues'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -eq '##vso[task.complete result=SucceededWithIssues]'
            }
        }
    }

    Context 'Local platform' {
        BeforeEach {
            Mock Write-Verbose { } -ModuleName 'CIHelpers' -Verifiable
        }

        It 'Logs all results via Write-Verbose' {
            Set-CITaskResult -Result 'Succeeded'
            Should -Invoke -CommandName Write-Verbose -ModuleName 'CIHelpers' -Times 1

            Set-CITaskResult -Result 'SucceededWithIssues'
            Should -Invoke -CommandName Write-Verbose -ModuleName 'CIHelpers' -Times 2

            Set-CITaskResult -Result 'Failed'
            Should -Invoke -CommandName Write-Verbose -ModuleName 'CIHelpers' -Times 3
        }
    }
}

#endregion

#region Publish-CIArtifact Tests

Describe 'Publish-CIArtifact' {
    BeforeAll {
        $script:testArtifactFile = Join-Path $TestDrive 'artifact.zip'
        $script:testOutputFile = Join-Path $TestDrive 'github-output.txt'
    }

    BeforeEach {
        Save-CIEnvironment
        Clear-MockCIEnvironment
        New-Item -Path $script:testArtifactFile -ItemType File -Force | Out-Null
        if (Test-Path $script:testOutputFile) {
            Remove-Item $script:testOutputFile -Force
        }
    }

    AfterEach {
        Restore-CIEnvironment
    }

    Context 'GitHub Actions platform' {
        BeforeEach {
            $env:GITHUB_ACTIONS = 'true'
            $env:GITHUB_OUTPUT = $script:testOutputFile
            Mock Write-Verbose { } -ModuleName 'CIHelpers'
        }

        It 'Sets output variables for artifact path and name' {
            Publish-CIArtifact -Path $script:testArtifactFile -Name 'test-artifact'
            $content = Get-Content -Path $script:testOutputFile -Raw
            $content | Should -BeLike '*artifact-path-test-artifact=*'
            $content | Should -BeLike '*artifact-name-test-artifact=test-artifact*'
        }

        It 'Logs confirmation via Write-Verbose' {
            Publish-CIArtifact -Path $script:testArtifactFile -Name 'my-artifact'
            Should -Invoke -CommandName Write-Verbose -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*my-artifact*'
            }
        }
    }

    Context 'Azure DevOps platform' {
        BeforeEach {
            $env:TF_BUILD = 'True'
            Mock Write-Host { } -ModuleName 'CIHelpers'
        }

        It 'Emits artifact.upload logging command' {
            Publish-CIArtifact -Path $script:testArtifactFile -Name 'test-artifact'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -match '##vso\[artifact\.upload containerfolder=test-artifact;artifactname=test-artifact\]'
            }
        }

        It 'Uses ContainerFolder parameter when specified' {
            Publish-CIArtifact -Path $script:testArtifactFile -Name 'my-artifact' -ContainerFolder 'custom-folder'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*containerfolder=custom-folder*'
            }
        }

        It 'Defaults ContainerFolder to Name when not specified' {
            Publish-CIArtifact -Path $script:testArtifactFile -Name 'default-name'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*containerfolder=default-name*'
            }
        }

        It 'Escapes special characters in container folder' {
            Publish-CIArtifact -Path $script:testArtifactFile -Name 'name' -ContainerFolder 'folder;name'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*containerfolder=folder%AZP3Bname*'
            }
        }

        It 'Escapes special characters in artifact name' {
            Publish-CIArtifact -Path $script:testArtifactFile -Name 'artifact[test]'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -like '*artifactname=artifact%AZP5Btest%AZP5D*'
            }
        }

        It 'Escapes special characters in path' {
            $pathWithChars = Join-Path $TestDrive 'path[with]brackets.zip'
            Mock Test-Path { $true } -ModuleName 'CIHelpers'
            $env:TF_BUILD = 'True'
            Publish-CIArtifact -Path $pathWithChars -Name 'artifact'
            Should -Invoke -CommandName Write-Host -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Object -match 'path%AZP5Bwith%AZP5Dbrackets\.zip'
            }
        }
    }

    Context 'Local platform' {
        BeforeEach {
            Mock Write-Verbose { } -ModuleName 'CIHelpers' -Verifiable
        }

        It 'Logs via Write-Verbose' {
            Publish-CIArtifact -Path $script:testArtifactFile -Name 'local-artifact'
            Should -Invoke -CommandName Write-Verbose -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*local-artifact*'
            }
        }
    }

    Context 'Path validation' {
        BeforeEach {
            Mock Write-Warning { } -ModuleName 'CIHelpers' -Verifiable
        }

        It 'Warns and returns when path does not exist' {
            Publish-CIArtifact -Path 'TestDrive:/nonexistent.zip' -Name 'artifact'
            Should -Invoke -CommandName Write-Warning -ModuleName 'CIHelpers' -Times 1 -ParameterFilter {
                $Message -like '*not found*'
            }
        }

        It 'Publishes when path is a directory' {
            $testDir = Join-Path $TestDrive 'artifact-dir'
            New-Item -Path $testDir -ItemType Directory -Force | Out-Null
            Mock Write-Verbose { } -ModuleName 'CIHelpers'
            $env:GITHUB_ACTIONS = 'true'
            $env:GITHUB_OUTPUT = $script:testOutputFile

            { Publish-CIArtifact -Path $testDir -Name 'dir-artifact' } | Should -Not -Throw
        }
    }
}

#endregion
