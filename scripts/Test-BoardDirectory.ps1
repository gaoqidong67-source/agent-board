[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$boardRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$errors = New-Object System.Collections.Generic.List[string]

function Test-OriginalPackageArchive {
    param(
        [string]$PackageRoot,
        [string]$Label
    )

    $originalRoot = Join-Path $PackageRoot '原包'
    $manifestPath = Join-Path $PackageRoot 'FILES.sha256'
    $auditPath = Join-Path $PackageRoot '来源与审查.md'
    if (-not (Test-Path -LiteralPath $originalRoot -PathType Container) -or
        -not (Test-Path -LiteralPath $manifestPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $auditPath -PathType Leaf)) {
        return
    }

    if (Test-Path -LiteralPath (Join-Path $originalRoot '.git')) {
        $errors.Add("Original package must not contain .git: $Label")
    }

    $expected = @{}
    foreach ($line in Get-Content -Encoding UTF8 -LiteralPath $manifestPath) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line -notmatch '^([0-9a-fA-F]{64})  (.+)$') {
            $errors.Add("Original package manifest has malformed line: $Label / $line")
            continue
        }

        $relativePath = $matches[2].Replace('\', '/')
        if ($expected.ContainsKey($relativePath)) {
            $errors.Add("Original package manifest has duplicate path: $Label / $relativePath")
            continue
        }
        $expected[$relativePath] = $matches[1].ToLowerInvariant()
    }

    $actual = @{}
    foreach ($file in Get-ChildItem -LiteralPath $originalRoot -Recurse -File -Force) {
        $relativePath = $file.FullName.Substring($originalRoot.Length + 1).Replace('\', '/')
        $actual[$relativePath] = $file.FullName
    }

    $missing = @($expected.Keys | Where-Object { -not $actual.ContainsKey($_) })
    $unlisted = @($actual.Keys | Where-Object { -not $expected.ContainsKey($_) })
    if ($missing.Count) {
        $errors.Add("Original package manifest references missing files: $Label / $($missing -join ', ')")
    }
    if ($unlisted.Count) {
        $errors.Add("Original package contains unlisted files: $Label / $($unlisted -join ', ')")
    }

    foreach ($relativePath in $expected.Keys) {
        if (-not $actual.ContainsKey($relativePath)) {
            continue
        }
        $actualHash = (Get-FileHash -LiteralPath $actual[$relativePath] -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $expected[$relativePath]) {
            $errors.Add("Original package hash mismatch: $Label / $relativePath")
        }
    }

    $audit = Get-Content -Raw -Encoding UTF8 -LiteralPath $auditPath
    if ($audit -notmatch '原包文件数：([0-9]+)') {
        $errors.Add("Source audit is missing original package file count: $Label")
    }
    elseif ([int]$matches[1] -ne $actual.Count) {
        $errors.Add("Source audit original package file count mismatch: $Label / declared $($matches[1]), actual $($actual.Count)")
    }
}

$requiredFiles = @(
    'README.md',
    '运行内核.md',
    '系统Agents\README.md',
    '系统Agents\协调者Agent.md',
    '系统Agents\综合决策Agent.md',
    '启动与运行规则.md',
    '评审流程.md',
    '基础席位.md',
    '成员管理规则.md',
    '输出模板.md',
    '成员Skills\README.md',
    '成员Skills\成员Skill模板.md',
    '架构参考\README.md',
    '架构参考\tianya-skills运行架构拆解.md',
    '蒸馏来源\README.md',
    '蒸馏来源\nuwa-skill\来源与审查.md',
    '蒸馏来源\nuwa-skill\FILES.sha256',
    '蒸馏来源\nuwa-skill\原包\SKILL.md',
    '决策记录\README.md'
)

foreach ($relative in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $boardRoot $relative))) {
        $errors.Add("Missing required file: $relative")
    }
}

foreach ($forbidden in @('SKILL.md', 'agents', 'members', 'references')) {
    if (Test-Path -LiteralPath (Join-Path $boardRoot $forbidden)) {
        $errors.Add("Standalone board directory must not retain top-level Skill shape: $forbidden")
    }
}

$readmePath = Join-Path $boardRoot 'README.md'
$rulesPath = Join-Path $boardRoot '启动与运行规则.md'
$kernelPath = Join-Path $boardRoot '运行内核.md'
if (Test-Path -LiteralPath $readmePath) {
    $readme = Get-Content -Raw -Encoding UTF8 -LiteralPath $readmePath
    foreach ($marker in @('启动董事会决策', '不是一个可独立触发的 Skill', '不读取本目录', '运行内核', '协调者 Agent', '综合决策 Agent', '最优可执行解')) {
        if ($readme -notmatch [regex]::Escape($marker)) {
            $errors.Add("README.md is missing boundary marker: $marker")
        }
    }
}
if (Test-Path -LiteralPath $rulesPath) {
    $rules = Get-Content -Raw -Encoding UTF8 -LiteralPath $rulesPath
    foreach ($marker in @('唯一启动条件', '不得启动、预读或主动建议启动', '不得为选人而批量读取')) {
        if ($rules -notmatch [regex]::Escape($marker)) {
            $errors.Add("启动与运行规则.md is missing boundary marker: $marker")
        }
    }
}
if (Test-Path -LiteralPath $kernelPath) {
    $kernel = Get-Content -Raw -Encoding UTF8 -LiteralPath $kernelPath
    foreach ($marker in @('共享决策包', '协调者 Agent', '综合决策 Agent', '任务信封', '议事卡.md', 'PASS', '180 个汉字', '当前最优解', '一次定向补充', '默认不读取', '信息隔离')) {
        if ($kernel -notmatch [regex]::Escape($marker)) {
            $errors.Add("运行内核.md is missing orchestration marker: $marker")
        }
    }
    $kernelLines = @(Get-Content -Encoding UTF8 -LiteralPath $kernelPath).Count
    if ($kernelLines -gt 170) {
        $errors.Add("运行内核.md exceeds context budget of 170 lines: $kernelLines")
    }
}

$coordinatorPath = Join-Path $boardRoot '系统Agents\协调者Agent.md'
if (Test-Path -LiteralPath $coordinatorPath) {
    $coordinator = Get-Content -Raw -Encoding UTF8 -LiteralPath $coordinatorPath
    foreach ($marker in @('定义 `Q`', '待研究问题 `R`', '独立任务信封', '信息隔离', '最多一次定向补充轮', '不预先锁定结论')) {
        if ($coordinator -notmatch [regex]::Escape($marker)) {
            $errors.Add("协调者Agent.md is missing contract marker: $marker")
        }
    }
    $coordinatorLines = @(Get-Content -Encoding UTF8 -LiteralPath $coordinatorPath).Count
    if ($coordinatorLines -gt 60) {
        $errors.Add("协调者Agent.md exceeds context budget of 60 lines: $coordinatorLines")
    }
}

$integratorPath = Join-Path $boardRoot '系统Agents\综合决策Agent.md'
if (Test-Path -LiteralPath $integratorPath) {
    $integrator = Get-Content -Raw -Encoding UTF8 -LiteralPath $integratorPath
    foreach ($marker in @('最优可执行解', '不按名气、人数', '组合方案', '硬边界 `B`', '最强反方', '失效')) {
        if ($integrator -notmatch [regex]::Escape($marker)) {
            $errors.Add("综合决策Agent.md is missing optimization marker: $marker")
        }
    }
    $integratorLines = @(Get-Content -Encoding UTF8 -LiteralPath $integratorPath).Count
    if ($integratorLines -gt 60) {
        $errors.Add("综合决策Agent.md exceeds context budget of 60 lines: $integratorLines")
    }
}

$architectureReviewPath = Join-Path $boardRoot '架构参考\tianya-skills运行架构拆解.md'
if (Test-Path -LiteralPath $architectureReviewPath) {
    $architectureReview = Get-Content -Raw -Encoding UTF8 -LiteralPath $architectureReviewPath
    foreach ($marker in @('https://github.com/momozi1996/tianya-skills', '5c4c29e0540089e0502147aee45610e4b1634f50', '许可证：MIT', '未安装、未运行', '硬编码', '仅学习架构')) {
        if ($architectureReview -notmatch [regex]::Escape($marker)) {
            $errors.Add("tianya-skills architecture review is missing marker: $marker")
        }
    }
}

$memberRoot = Join-Path $boardRoot '成员Skills'
$memberIndexPath = Join-Path $memberRoot 'README.md'
$memberIndex = if (Test-Path -LiteralPath $memberIndexPath) {
    Get-Content -Raw -Encoding UTF8 -LiteralPath $memberIndexPath
} else {
    ''
}
if ($memberIndex) {
    foreach ($marker in @('视角簇', '首轮议事卡', 'PASS', '召开时到此停止')) {
        if ($memberIndex -notmatch [regex]::Escape($marker)) {
            $errors.Add("成员Skills/README.md is missing routing marker: $marker")
        }
    }
    $memberIndexLines = @(Get-Content -Encoding UTF8 -LiteralPath $memberIndexPath).Count
    if ($memberIndexLines -gt 60) {
        $errors.Add("成员Skills/README.md exceeds runtime routing budget of 60 lines: $memberIndexLines")
    }
}
$members = @()
if (Test-Path -LiteralPath $memberRoot) {
    $members = @(Get-ChildItem -LiteralPath $memberRoot -Directory -Force)
}

foreach ($member in $members) {
    $cardPath = Join-Path $member.FullName '议事卡.md'
    $skillPath = Join-Path $member.FullName 'SKILL.md'
    $auditPath = Join-Path $member.FullName '来源与审查.md'
    $manifestPath = Join-Path $member.FullName 'FILES.sha256'
    $originalSkillPath = Join-Path $member.FullName '原包\SKILL.md'
    if (-not (Test-Path -LiteralPath $skillPath)) {
        $errors.Add("Member directory is missing SKILL.md: $($member.Name)")
        continue
    }
    foreach ($requiredMemberFile in @($cardPath, $auditPath, $manifestPath, $originalSkillPath)) {
        if (-not (Test-Path -LiteralPath $requiredMemberFile)) {
            $errors.Add("Member directory is missing third-party archive file: $($member.Name) / $requiredMemberFile")
        }
    }
    if ($memberIndex -notmatch [regex]::Escape($member.Name)) {
        $errors.Add("Member is not referenced by 成员Skills/README.md: $($member.Name)")
    }
    if (Test-Path -LiteralPath $cardPath) {
        $card = Get-Content -Raw -Encoding UTF8 -LiteralPath $cardPath
        foreach ($marker in @('视角簇：', '入选条件：', '跳过条件：', '独有问题：', '重点风险：', '反证信号：', '首轮要求：', 'PASS', '180 个汉字')) {
            if ($card -notmatch [regex]::Escape($marker)) {
                $errors.Add("Member 议事卡.md is missing marker '$marker': $($member.Name)")
            }
        }
        $cardLines = @(Get-Content -Encoding UTF8 -LiteralPath $cardPath).Count
        if ($cardLines -gt 16) {
            $errors.Add("Member 议事卡.md exceeds context budget of 16 lines: $($member.Name) / $cardLines")
        }
    }

    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $skillPath
    $frontmatter = [regex]::Match($content, '(?s)\A---\r?\n(.*?)\r?\n---')
    if (-not $frontmatter.Success) {
        $errors.Add("Member SKILL.md has malformed frontmatter: $($member.Name)")
        continue
    }
    foreach ($marker in @('仅供董事会', '不得独立触发', '不代表真人')) {
        if ($frontmatter.Groups[1].Value -notmatch [regex]::Escape($marker)) {
            $errors.Add("Member description is missing marker '$marker': $($member.Name)")
        }
    }
    foreach ($heading in @('## 定位与边界', '## 来源基础', '## 核心判断模型', '## 评审问题', '## 常见盲区', '## 输出要求')) {
        if ($content -notmatch ('(?m)^' + [regex]::Escape($heading) + '\s*$')) {
            $errors.Add("Member SKILL.md is missing heading '$heading': $($member.Name)")
        }
    }
    foreach ($marker in @('仅在首轮意见能改变结论', '不复述共享决策包', '只提交研究意见')) {
        if ($content -notmatch [regex]::Escape($marker)) {
            $errors.Add("Member deep-review contract is missing marker '$marker': $($member.Name)")
        }
    }
    if (Test-Path -LiteralPath $auditPath) {
        $audit = Get-Content -Raw -Encoding UTF8 -LiteralPath $auditPath
        foreach ($marker in @('仓库：', '固定提交：', '许可证：', '风险等级：', '原包只读')) {
            if ($audit -notmatch [regex]::Escape($marker)) {
                $errors.Add("Member source audit is missing marker '$marker': $($member.Name)")
            }
        }
    }
    Test-OriginalPackageArchive -PackageRoot $member.FullName -Label "member $($member.Name)"
}

$nuwaRoot = Join-Path $boardRoot '蒸馏来源\nuwa-skill'
Test-OriginalPackageArchive -PackageRoot $nuwaRoot -Label 'nuwa-skill'

if ($errors.Count) {
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output "Board directory validation OK. Registered member directories: $($members.Count)"
exit 0

