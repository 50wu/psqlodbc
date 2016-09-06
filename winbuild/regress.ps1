<#
.SYNOPSIS
    Build all dlls of psqlodbc project using MSbuild.
.DESCRIPTION
    Build test programs and run them.
.PARAMETER Target
    Specify the target of MSBuild. "Build"(default) or
    "Clean" is available.
.PARAMETER VCVersion
    Visual Studio version is determined automatically unless this
    option is specified.
.PARAMETER Platform
    Specify build platforms, "Win32"(default), "x64" or "both" is available.
.PARAMETER Toolset
    MSBuild PlatformToolset is determined automatically unless this
    option is specified. Currently "v100", "Windows7.1SDK", "v110",
    "v110_xp", "v120", "v120_xp", "v140" or "v140_xp" is available.
.PARAMETER MSToolsVersion
    MSBuild ToolsVersion is detemrined automatically unless this
    option is specified.  Currently "4.0", "12.0" or "14.0" is available.
.PARAMETER Configuration
    Specify "Release"(default) or "Debug".
.PARAMETER BuildConfigPath
    Specify the configuration xml file name if you want to use
    the configuration file other than standard one.
    The relative path is relative to the current directory.
.EXAMPLE
    > .\regress
	Build with default or automatically selected parameters
	and run them.
.EXAMPLE
    > .\regress Clean
	Clean all generated files.
.EXAMPLE
    > .\regress -V(CVersion) 14.0
	Build using Visual Studio 11.0 environment.
.EXAMPLE
    > .\regress -P(latform) x64
	Build only 64bit dlls.
.NOTES
    Author: Hiroshi Inoue
    Date:   August 2, 2016
#>

#
#	build 32bit & 64bit dlls for VC10 or later
#
Param(
[ValidateSet("Build", "Clean")]
[string]$Target="Build",
[string]$VCVersion,
[ValidateSet("Win32", "x64", "both")]
[string]$Platform="Win32",
[string]$Toolset,
[ValidateSet("", "4.0", "12.0", "14.0")]
[string]$MSToolsVersion,
[ValidateSet("Debug", "Release")]
[String]$Configuration="Release",
[string]$BuildConfigPath
)


function vcxfile_make($testsf, $vcxfile, $usingExe)
{
	$testnames=@()
	$testexes=@()
	$f = (Get-Content -Path $testsf) -as [string[]]
	$nstart=$false
	foreach ($l in $f) {
		if ($l[0] -eq "#") {
			continue
		}
		$sary=-split $l
		if ($sary[0] -eq "#") {
			continue
		}
		if ($sary[0] -eq "TESTBINS") {
			$nstart=$true
			$sary[0]=$null
			if ($sary[1] -eq "=") {
				$sary[1]=$null
			}
		}
		if ($nstart) {
			if ($sary[$sary.length - 1] -eq "\") {
				$sary[$sary.length - 1] = $null
			} else {
				$nstart=$false
			}
			$testnames+=$sary
			if (-not $nstart) {
				break
			}
		}
	}
	for ($i=0; $i -lt $testnames.length; $i++) {
		Write-Debug "$i : $testnames[$i]"
	}
# here-string
	@'
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <!--
	 This file is automatically generated by regress.ps1
	 and used by MSBuild.
    -->
    <PropertyGroup>
	<Configuration>Release</Configuration>
	<srcPath>..\test\src\</srcPath>
    </PropertyGroup>
    <Target Name="Build">
        <MSBuild Projects="regress_one.vcxproj"
	  Targets="ClCompile"
	  Properties="TestName=common;Configuration=$(Configuration);srcPath=$(srcPath)"/>
'@ > $vcxfile

	foreach ($testbin in $testnames) {
		if ("$testbin" -eq "") {
			continue
		}
		$sary=$testbin.split("/")
		$testname=$sary[$sary.length -1]
		$dirname=""
		for ($i=0;$i -lt $sary.length - 1;$i++) {
			$dirname+=($sary[$i]+"`\")
		}
		Write-Debug "testname=$testname dirname=$dirname"
		if ($usingExe) {
			$testexes+=($dirname+$testname+".exe")
		} else {
			$testexes+=$testname.Replace("-test","")
		}
# here-string
		@"
        <MSBuild Projects="regress_one.vcxproj"
	  Targets="Build"
	  Properties="TestName=$testname;Configuration=`$(Configuration);srcPath=`$(srcPath);SubDir=$dirname"/>
"@ >> $vcxfile
	}
# here-string
	@'
        <MSBuild Projects="regress_one.vcxproj"
	  Targets="Build"
	  Properties="TestName=runsuite;Configuration=$(Configuration);srcPath=$(srcPath)..\"/>
        <MSBuild Projects="regress_one.vcxproj"
	  Targets="Build"
	  Properties="TestName=reset-db;Configuration=$(Configuration);srcPath=$(srcPath)..\"/>
    </Target>
    <Target Name="Clean">
        <MSBuild Projects="regress_one.vcxproj"
	  Targets="Clean"
	  Properties="Configuration=$(Configuration);srcPath=$(srcPath)"/>
    </Target>
</Project>
'@ >> $vcxfile

	return $testexes
}

function RunTest($scriptPath, $Platform)
{
	# Run regression tests
	if ($Platform -eq "x64") {
		$targetdir="test_x64"
	} else {
		$targetdir="test_x86"
	}
	$revsdir="..\"
	$origdir="${revsdir}..\test"

	pushd $scriptPath\$targetdir

	$regdiff="regression.diffs"
	$RESDIR="results"
	if (Test-Path $regdiff) {
		Remove-Item $regdiff
	}
	New-Item $RESDIR -ItemType Directory -Force > $null
	Get-Content "${origdir}\sampletables.sql" | .\reset-db
	.\runsuite $TESTEXES --inputdir=$origdir

	popd
}

$usingExe=$false
$testsf="..\test\tests"
Write-Debug testsf=$testsf
$vcxfile="./generated_regress.vcxproj"

$TESTEXES=vcxfile_make $testsf $vcxfile $usingExe

$scriptPath = (Split-Path $MyInvocation.MyCommand.Path)
$configInfo = & "$scriptPath\configuration.ps1" "$BuildConfigPath"
Import-Module ${scriptPath}\MSProgram-Get.psm1
$msbuildexe=Find-MSBuild ([ref]$VCVersion) ([ref]$MSToolsVersion) ([ref]$Toolset) $configInfo

if ($Platform -ieq "both") {
	$pary = @("Win32", "x64")
} else {
	$pary = @($Platform)
}

foreach ($pl in $pary) {
	invoke-expression -Command "& `"${msbuildexe}`" $vcxfile /tv:$MSToolsVersion /p:Platform=$pl``;Configuration=$Configuration``;PlatformToolset=${Toolset} /t:$target /p:VisualStudioVersion=${VisualStudioVersion} /Verbosity:minimal"

	if ($target -ieq "Clean") {
		continue
	}

	RunTest $scriptPath $pl $TESTEXES
}
