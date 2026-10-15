param([string]$Config = 'gamer.config.json', [string]$SnapshotPath = '', [string]$DemoSearch = '', [switch]$Headless, [string[]]$InstallIds = @(), [string]$Action = 'install', [string]$LogFile = '', [switch]$AutoTest, [string]$ResultFile = '')

# Shared installer window (cartoon style) around winget. Which programs it shows comes from a config file.
# Nothing is installed until you press "Install selected" and confirm.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgPath = if ([IO.Path]::IsPathRooted($Config)) { $Config } else { Join-Path $here $Config }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
function Resolve-Here($p) { if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $here $p } }
$catalog = Get-Content (Resolve-Here $cfg.catalog) -Raw | ConvertFrom-Json
$iconFile = Resolve-Here $cfg.icons
$iconDir = if ($cfg.iconDir) { $cfg.iconDir } else { 'icons' }
$presetFile = if ($cfg.presets) { Resolve-Here $cfg.presets } else { $null }
$presets = if ($presetFile -and (Test-Path $presetFile)) { @(Get-Content $presetFile -Raw | ConvertFrom-Json) } else { @() }
$icons = if (Test-Path $iconFile) { Get-Content $iconFile -Raw | ConvertFrom-Json } else { $null }
$tick = [string][char]0x2714
$cross = [string][char]0x2716

# Programs ticked (green) when the window opens. Everything else starts red.
$starter = @($cfg.starter)
$script:hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)

# The worker does the real work. It runs in the background for the window, or directly with -Headless.
$script:worker = {
    param($items, $q, $state, $action, $logFile)
    function Say($m) {
        $q.Enqueue("LOG|$m")
        if ($logFile) { try { Add-Content -LiteralPath $logFile -Value $m -Encoding UTF8 } catch { } }
    }
    function Reason($text, $code) {
        if ($text -match 'No package found|No installed package found') { return 'winget could not find it (its ID may have changed).' }
        if ($text -match 'hash does not match|hash mismatch') { return 'the download failed its safety check. Try again.' }
        if ($text -match 'Failed when searching source|0x8a15000f|0x80072ee7|0x80072efd|0x80072efe|unable to resolve|timed out|No internet|network') { return 'could not reach the internet or the package source.' }
        if ($text -match 'Microsoft Store|msstore|0x80d02017|0x80073d') { return 'the Microsoft Store could not install it. Open the Store, sign in, and try again.' }
        if ($text -match 'administrator|elevat|0x80070005|Access is denied') { return 'it needs administrator permission. Use the (Admin) launcher.' }
        if ($text -match 'disk space|0x80070070') { return 'not enough free disk space.' }
        if ($text -match 'in use|being used by another process') { return 'the program is open. Close it and try again.' }
        if ($text -match 'installer failed with exit code:?\s*(\d+)') { return "its installer failed (exit code $($Matches[1]))." }
        $last = ($text -split "`r?`n" | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^[\s\-\\|/]+$' } | Select-Object -Last 1)
        if ($last) { return $last.Trim() }
        return "unknown problem (code $code)"
    }
    $verb = if ($action -eq 'upgrade') { 'upgrade' } else { 'install' }
    $ok = 0; $fail = 0; $failedIds = @(); $restart = @(); $i = 0
    foreach ($p in $items) {
        if ($state.Cancel) { Say 'Stopped before the remaining programs.'; break }
        $i++
        $q.Enqueue("PROGRESS|$i|$($items.Count)|$($p.name)")
        $a = @($verb, '--id', $p.id, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
        if ($p.source -eq 'msstore') { $a += @('--source', 'msstore') }
        $text = ''; $code = 1
        try { $text = (& winget @a 2>&1 | Out-String); $code = $LASTEXITCODE } catch { $text = $_.Exception.Message }
        $already = ($code -eq -1978335189) -or ($text -match 'already installed|No available upgrade found|No newer package versions')
        if ($code -eq 0 -and -not $already) {
            $ok++
            $needs = ($p.restart -eq $true) -or ($text -match 'restart (is )?required|reboot (is )?required|restart your (computer|PC)')
            if ($needs) { $restart += $p.name }
            Say ('OK         {0}{1}' -f $p.name, $(if ($needs) { '  (restart needed)' } else { '' }))
            $q.Enqueue("OKID|$($p.id)")
        } elseif ($already -or $code -eq 3010) {
            $ok++
            if ($code -eq 3010) { $restart += $p.name }
            Say ('{0} {1}' -f $(if ($verb -eq 'upgrade') { 'UP TO DATE ' } else { 'ALREADY    ' }), $p.name)
            $q.Enqueue("OKID|$($p.id)")
        } else {
            $fail++; $failedIds += $p.id
            Say ('FAILED     {0} - {1}' -f $p.name, (Reason $text $code))
            if ($logFile) { try { Add-Content -LiteralPath $logFile -Value ("    [winget output]`r`n" + (($text.Trim() -split "`r?`n" | ForEach-Object { '      ' + $_ }) -join "`r`n")) -Encoding UTF8 } catch { } }
        }
    }
    $q.Enqueue("DONE|$ok|$fail|" + ($failedIds -join ',') + '|' + ($restart -join ', '))
}

if ($Headless) {
    # No window: install the given IDs straight from the catalog and print what happened (used for testing).
    $InstallIds = @($InstallIds | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
    $pkgs = @($catalog | Where-Object { $InstallIds -contains $_.id })
    $hq = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
    $hs = [hashtable]::Synchronized(@{ Cancel = $false })
    & $script:worker $pkgs $hq $hs $Action $(if ($LogFile) { $LogFile } else { $null })
    $m = $null
    while ($hq.TryDequeue([ref]$m)) { Write-Output $m }
    return
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Gamer &amp; Streamer Installer" Width="1260" Height="820" MinWidth="820" MinHeight="560"
        Background="#10294A" WindowStartupLocation="CenterScreen" FontFamily="Segoe UI" ShowActivated="False">
  <Window.Resources>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="16"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Border Background="#0B1F3A" CornerRadius="8" BorderBrush="#06142B" BorderThickness="2" Margin="2,0,0,0">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.DecreaseRepeatButton><RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0"/></Track.DecreaseRepeatButton>
                <Track.IncreaseRepeatButton><RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0"/></Track.IncreaseRepeatButton>
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb"><Border Background="#5B93D6" CornerRadius="6" BorderBrush="#06142B" BorderThickness="2" Margin="1"/></ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Chip" TargetType="ToggleButton">
      <Setter Property="Margin" Value="5,5,9,11"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="bd" CornerRadius="14" Background="#E2504E" BorderBrush="#06142B" BorderThickness="3" Padding="6,10,6,6" Width="170" Height="186">
              <Border.Effect><DropShadowEffect BlurRadius="0" ShadowDepth="4" Direction="315" Color="#06142B" Opacity="1"/></Border.Effect>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Top"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True"><Setter TargetName="bd" Property="Background" Value="#35B565"/></Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="RenderTransform"><Setter.Value><TranslateTransform Y="-2"/></Setter.Value></Setter></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Pill" TargetType="Button">
      <Setter Property="Padding" Value="14,5"/>
      <Setter Property="Margin" Value="0,0,10,0"/>
      <Setter Property="Foreground" Value="#06142B"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="16" Background="#FFE066" BorderBrush="#06142B" BorderThickness="2.5" Padding="{TemplateBinding Padding}">
              <Border.Effect><DropShadowEffect BlurRadius="0" ShadowDepth="3" Direction="315" Color="#06142B" Opacity="1"/></Border.Effect>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#FFEE9A"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Go" TargetType="Button">
      <Setter Property="Padding" Value="28,14"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontSize" Value="18"/>
      <Setter Property="FontFamily" Value="Segoe UI Black"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="bd" CornerRadius="16" Background="#2FAE5C" BorderBrush="#06142B" BorderThickness="3.5" Padding="{TemplateBinding Padding}">
              <Border.Effect><DropShadowEffect BlurRadius="0" ShadowDepth="5" Direction="315" Color="#06142B" Opacity="1"/></Border.Effect>
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="Background" Value="#3CC96F"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="bd" Property="Background" Value="#8FA9BF"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid Margin="22">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,14">
      <TextBlock x:Name="Heading" Text="Installer" FontSize="36" FontFamily="Segoe UI Black" Foreground="White">
        <TextBlock.Effect><DropShadowEffect BlurRadius="0" ShadowDepth="4" Direction="315" Color="#06142B" Opacity="1"/></TextBlock.Effect>
      </TextBlock>
      <TextBlock x:Name="Sub" Text="" FontSize="15" FontWeight="SemiBold" Foreground="#BFD9F5" Margin="2,10,0,12"/>
      <WrapPanel>
        <Border Background="#35B565" BorderBrush="#06142B" BorderThickness="2.5" CornerRadius="10" Padding="12,4" Margin="0,0,10,0"><TextBlock Text="GREEN = will be installed" Foreground="White" FontWeight="Bold"/></Border>
        <Border Background="#E2504E" BorderBrush="#06142B" BorderThickness="2.5" CornerRadius="10" Padding="12,4" Margin="0,0,26,0"><TextBlock Text="RED = skipped" Foreground="White" FontWeight="Bold"/></Border>
        <Button x:Name="BtnAll" Content="Select everything" Style="{StaticResource Pill}"/>
        <Button x:Name="BtnNone" Content="Clear everything" Style="{StaticResource Pill}"/>
        <Border Width="270" Height="34" Background="#FFFFFF" BorderBrush="#06142B" BorderThickness="2.5" CornerRadius="17" Margin="14,0,0,0">
          <Border.Effect><DropShadowEffect BlurRadius="0" ShadowDepth="3" Direction="315" Color="#06142B" Opacity="1"/></Border.Effect>
          <Grid>
            <TextBox x:Name="Search" Background="Transparent" BorderThickness="0" FontSize="14" VerticalContentAlignment="Center" Padding="14,0,10,0" Foreground="#06142B"/>
            <TextBlock x:Name="SearchHint" Text="Search programs..." IsHitTestVisible="False" Foreground="#7B93B0" FontSize="14" VerticalAlignment="Center" Margin="16,0,0,0"/>
          </Grid>
        </Border>
        <Button x:Name="BtnSave" Content="Save my picks" Style="{StaticResource Pill}" Margin="14,0,10,0"/>
        <Button x:Name="BtnLoad" Content="Load picks" Style="{StaticResource Pill}"/>
      </WrapPanel>
      <WrapPanel x:Name="Presets" Margin="0,14,0,0" Visibility="Collapsed">
        <TextBlock Text="QUICK PICKS" FontFamily="Segoe UI Black" FontSize="13" Foreground="#FFE066" VerticalAlignment="Center" Margin="2,0,12,0"/>
      </WrapPanel>
    </StackPanel>
    <ScrollViewer x:Name="Scroll" Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,10,0">
      <StackPanel x:Name="Cats"/>
    </ScrollViewer>
    <Border Grid.Row="2" Background="#1B3F6E" CornerRadius="16" Padding="16" Margin="0,14,6,6" BorderBrush="#06142B" BorderThickness="3.5">
      <Border.Effect><DropShadowEffect BlurRadius="0" ShadowDepth="5" Direction="315" Color="#06142B" Opacity="1"/></Border.Effect>
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" Margin="0,0,18,0" VerticalAlignment="Center">
          <TextBlock x:Name="Status" FontSize="15" Foreground="#FFFFFF" FontWeight="Bold" Text="Ready"/>
          <ProgressBar x:Name="Bar" Height="14" Margin="0,8,0,0" Minimum="0" Maximum="100" Value="0" Visibility="Collapsed" Foreground="#35B565" Background="#0B1F3A" BorderBrush="#06142B" BorderThickness="2"/>
          <WrapPanel Margin="0,10,0,0">
            <Button x:Name="BtnCancel" Content="Stop after this program" Style="{StaticResource Pill}" Visibility="Collapsed"/>
            <Button x:Name="BtnRetry" Content="Retry failed" Style="{StaticResource Pill}" Visibility="Collapsed"/>
            <Button x:Name="BtnUpdate" Content="Update installed programs" Style="{StaticResource Pill}" Visibility="Collapsed"/>
            <Button x:Name="BtnLog" Content="Open install log" Style="{StaticResource Pill}" Visibility="Collapsed"/>
            <Button x:Name="BtnWinget" Content="Get winget from the Microsoft Store" Style="{StaticResource Pill}" Visibility="Collapsed"/>
          </WrapPanel>
          <TextBox x:Name="Log" Height="90" Margin="0,8,0,0" IsReadOnly="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap" FontFamily="Consolas" FontSize="12" Visibility="Collapsed" Background="#0B1F3A" Foreground="#DCE9F7" BorderBrush="#06142B" BorderThickness="2"/>
        </StackPanel>
        <Button x:Name="BtnInstall" Grid.Column="1" Content="Install selected" Style="{StaticResource Go}" VerticalAlignment="Center" Margin="0,0,8,6"/>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$cats = $win.FindName('Cats')
$win.Title = $cfg.title
$win.FindName('Heading').Text = $cfg.title
$win.FindName('Sub').Text = $cfg.subtitle
$presetRow = $win.FindName('Presets')
$status = $win.FindName('Status')
$bar = $win.FindName('Bar')
$log = $win.FindName('Log')
$btnInstall = $win.FindName('BtnInstall')
$btnAll = $win.FindName('BtnAll')
$btnNone = $win.FindName('BtnNone')
$search = $win.FindName('Search')
$searchHint = $win.FindName('SearchHint')
$btnCancel = $win.FindName('BtnCancel')
$btnRetry = $win.FindName('BtnRetry')
$btnUpdate = $win.FindName('BtnUpdate')
$btnLog = $win.FindName('BtnLog')
$btnWinget = $win.FindName('BtnWinget')
$btnSave = $win.FindName('BtnSave')
$btnLoad = $win.FindName('BtnLoad')
$script:state = [hashtable]::Synchronized(@{ Cancel = $false })

$script:sections = @()
$script:installing = $false
$bc = New-Object Windows.Media.BrushConverter
$outline = $bc.ConvertFromString('#06142B')
$badgeColors = @('#E8833A', '#8E5BD6', '#2F9BD6', '#D6477A', '#3AA876', '#C7A21F', '#D65A3A', '#4F6BD6')

function New-HardShadow($depth) {
    $e = New-Object Windows.Media.Effects.DropShadowEffect
    $e.BlurRadius = 0
    $e.ShadowDepth = $depth
    $e.Direction = 315
    $e.Color = [Windows.Media.ColorConverter]::ConvertFromString('#06142B')
    $e.Opacity = 1
    return $e
}

# A round white badge with the program's logo (or a coloured letter if there is no logo).
function New-IconBadge($pkg) {
    $size = 60
    $ring = New-Object Windows.Controls.Border
    $ring.Width = $size
    $ring.Height = $size
    $ring.CornerRadius = 14
    $ring.BorderBrush = $outline
    $ring.BorderThickness = 3
    $ring.HorizontalAlignment = 'Center'
    $ring.Margin = '0,0,0,7'
    $logo = $null
    if ($icons) { $logo = $icons.PSObject.Properties[$pkg.id] }
    $pngPath = $null
    if ($logo -and $logo.Value.file) { $pngPath = Join-Path $here ($iconDir + "\" + $logo.Value.file) }
    if ($pngPath -and (Test-Path $pngPath)) {
        $ring.Background = [Windows.Media.Brushes]::White
        $bi = New-Object Windows.Media.Imaging.BitmapImage
        $bi.BeginInit()
        $bi.CacheOption = 'OnLoad'
        $bi.UriSource = New-Object Uri($pngPath)
        $bi.EndInit()
        $bi.Freeze()
        $im = New-Object Windows.Controls.Image
        $im.Source = $bi
        $im.Width = 40
        $im.Height = 40
        $im.Stretch = 'Uniform'
        [Windows.Media.RenderOptions]::SetBitmapScalingMode($im, 'HighQuality')
        $ring.Child = $im
    } elseif ($logo -and $logo.Value.path) {
        $ring.Background = [Windows.Media.Brushes]::White
        $path = New-Object Windows.Shapes.Path
        $path.Data = [Windows.Media.Geometry]::Parse($logo.Value.path)
        $path.Stretch = 'Uniform'
        $path.Width = 32
        $path.Height = 32
        $col = $logo.Value.color
        if ($col -match '^#(0{6}|10{5}|10{3}10|231F20|1C1E20|302E31|313131)$') { $col = '#1B2A41' }
        $path.Fill = $bc.ConvertFromString($col)
        $ring.Child = $path
    } else {
        $sum = 0
        foreach ($ch in $pkg.name.ToCharArray()) { $sum += [int]$ch }
        $ring.Background = $bc.ConvertFromString($badgeColors[$sum % $badgeColors.Count])
        $tx = New-Object Windows.Controls.TextBlock
        $tx.Text = $pkg.name.Substring(0, 1).ToUpper()
        $tx.FontFamily = 'Segoe UI Black'
        $tx.FontSize = 28
        $tx.Foreground = [Windows.Media.Brushes]::White
        $tx.HorizontalAlignment = 'Center'
        $tx.VerticalAlignment = 'Center'
        $ring.Child = $tx
    }
    return $ring
}
function Set-ChipLook($tb) {
    $mark = if ($tb.IsChecked) { $tick } else { $cross }
    $tb.Tag.Label.Text = $mark + ' ' + $tb.Tag.Pkg.name
}

function Update-Counts {
    $total = 0
    foreach ($s in $script:sections) {
        $n = @($s.Chips | Where-Object { $_.IsChecked }).Count
        $total += $n
        $s.Count.Text = "$n of $($s.Chips.Count) selected"
    }
    $btnInstall.Content = "Install selected ($total)"
    $btnInstall.IsEnabled = ($total -gt 0 -and -not $script:installing -and $script:hasWinget)
    if (-not $script:installing) {
        $status.Text = if (-not $script:hasWinget) { 'winget (Windows Package Manager) was not found, so nothing can be installed yet. Get "App Installer" from the Microsoft Store.' }
                       elseif ($total -eq 0) { 'Pick at least one program to install.' }
                       else { "$total program(s) will be installed." }
    }
}

foreach ($g in ($catalog | Group-Object category)) {
    $box = New-Object Windows.Controls.Border
    $box.Background = $bc.ConvertFromString('#1B3F6E')
    $box.BorderBrush = $outline
    $box.BorderThickness = 3.5
    $box.CornerRadius = 18
    $box.Padding = 16
    $box.Margin = '0,0,8,18'
    $box.Effect = New-HardShadow 5

    $stack = New-Object Windows.Controls.StackPanel
    $head = New-Object Windows.Controls.DockPanel
    $head.Margin = '0,0,0,6'

    $btnRow = New-Object Windows.Controls.StackPanel
    $btnRow.Orientation = 'Horizontal'
    [Windows.Controls.DockPanel]::SetDock($btnRow, 'Right')
    $bAll = New-Object Windows.Controls.Button
    $bAll.Content = 'All'
    $bAll.Style = $win.FindResource('Pill')
    $bNone = New-Object Windows.Controls.Button
    $bNone.Content = 'None'
    $bNone.Style = $win.FindResource('Pill')
    $bNone.Margin = '0,0,4,0'
    [void]$btnRow.Children.Add($bAll)
    [void]$btnRow.Children.Add($bNone)
    [void]$head.Children.Add($btnRow)

    $titleRow = New-Object Windows.Controls.StackPanel
    $titleRow.Orientation = 'Horizontal'
    $t = New-Object Windows.Controls.TextBlock
    $t.Text = $g.Name
    $t.FontSize = 22
    $t.FontFamily = 'Segoe UI Black'
    $t.Foreground = $bc.ConvertFromString('#8FD0FF')
    $cnt = New-Object Windows.Controls.TextBlock
    $cnt.FontSize = 13
    $cnt.FontWeight = 'Bold'
    $cnt.Foreground = $bc.ConvertFromString('#A9C6E6')
    $cnt.Margin = '14,9,0,0'
    [void]$titleRow.Children.Add($t)
    [void]$titleRow.Children.Add($cnt)
    [void]$head.Children.Add($titleRow)
    [void]$stack.Children.Add($head)

    $wrap = New-Object Windows.Controls.WrapPanel
    $chips = New-Object System.Collections.ArrayList
    foreach ($p in $g.Group) {
        $tb = New-Object Windows.Controls.Primitives.ToggleButton
        $tb.Style = $win.FindResource('Chip')
        $tb.ToolTip = "$($p.description)`n$($p.id)"

        $col = New-Object Windows.Controls.StackPanel
        $col.HorizontalAlignment = 'Center'
        [void]$col.Children.Add((New-IconBadge $p))
        $label = New-Object Windows.Controls.TextBlock
        $label.TextWrapping = 'Wrap'
        $label.TextAlignment = 'Center'
        $label.MaxWidth = 150
        $label.HorizontalAlignment = 'Center'
        [void]$col.Children.Add($label)
        $desc = New-Object Windows.Controls.TextBlock
        $desc.Text = $p.description
        $desc.FontSize = 10.5
        $desc.FontWeight = 'Normal'
        $desc.TextWrapping = 'Wrap'
        $desc.TextAlignment = 'Center'
        $desc.MaxWidth = 150
        $desc.HorizontalAlignment = 'Center'
        $desc.Foreground = $bc.ConvertFromString('#F2F8FF')
        $desc.Opacity = 0.92
        $desc.Margin = '0,4,0,0'
        [void]$col.Children.Add($desc)
        $inst = New-Object Windows.Controls.TextBlock
        $inst.Text = 'Installed on this PC'
        $inst.FontSize = 10
        $inst.FontWeight = 'SemiBold'
        $inst.TextAlignment = 'Center'
        $inst.HorizontalAlignment = 'Center'
        $inst.Foreground = $bc.ConvertFromString('#E8FFD0')
        $inst.Visibility = 'Collapsed'
        $inst.Margin = '0,2,0,0'
        [void]$col.Children.Add($inst)
        $tb.Content = $col
        $tb.Tag = [pscustomobject]@{ Pkg = $p; Label = $label; Installed = $inst }
        $tb.IsChecked = ($starter -contains $p.id)
        Set-ChipLook $tb
        $tb.Add_Click({ Set-ChipLook $this; Update-Counts })
        [void]$chips.Add($tb)
        [void]$wrap.Children.Add($tb)
    }
    [void]$stack.Children.Add($wrap)
    $box.Child = $stack
    [void]$cats.Children.Add($box)

    $sec = [pscustomobject]@{ Name = $g.Name; Chips = $chips; Count = $cnt; Box = $box }
    $script:sections += $sec
    $bAll.Tag = $chips
    $bNone.Tag = $chips
    $bAll.Add_Click({ foreach ($c in $this.Tag) { $c.IsChecked = $true; Set-ChipLook $c }; Update-Counts })
    $bNone.Add_Click({ foreach ($c in $this.Tag) { $c.IsChecked = $false; Set-ChipLook $c }; Update-Counts })
}

function Update-Filter {
    $q = $search.Text.Trim()
    $searchHint.Visibility = if ($search.Text.Length -eq 0) { 'Visible' } else { 'Collapsed' }
    foreach ($s in $script:sections) {
        $shown = 0
        foreach ($c in $s.Chips) {
            $p = $c.Tag.Pkg
            $hit = ($q -eq '') -or ($p.name -like "*$q*") -or ($p.description -like "*$q*") -or ($p.id -like "*$q*")
            $c.Visibility = if ($hit) { 'Visible' } else { 'Collapsed' }
            if ($hit) { $shown++ }
        }
        $s.Box.Visibility = if ($shown -gt 0) { 'Visible' } else { 'Collapsed' }
    }
}
$search.Add_TextChanged({ Update-Filter })
$search.Add_KeyDown({ if ($_.Key -eq 'Escape') { $search.Text = '' } })

$btnAll.Add_Click({ foreach ($s in $script:sections) { foreach ($c in $s.Chips) { $c.IsChecked = $true; Set-ChipLook $c } }; Update-Counts })
$btnNone.Add_Click({ foreach ($s in $script:sections) { foreach ($c in $s.Chips) { $c.IsChecked = $false; Set-ChipLook $c } }; Update-Counts })

# ---- installing / updating -------------------------------------------------------
$script:queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$script:failed = @()
$script:updatable = @()
$script:lastLog = $null
$logDir = Join-Path $env:LOCALAPPDATA 'PCInstallers\logs'

function Set-Busy($busy) {
    $script:installing = $busy
    foreach ($s in $script:sections) { foreach ($c in $s.Chips) { $c.IsEnabled = -not $busy } }
    foreach ($b in @($btnAll, $btnNone, $btnSave, $btnLoad)) { $b.IsEnabled = -not $busy }
    $presetRow.IsEnabled = -not $busy
}

function Show-Actions {
    $idle = -not $script:installing
    $btnRetry.Visibility = if ($idle -and $script:failed.Count -gt 0) { 'Visible' } else { 'Collapsed' }
    $btnRetry.Content = "Retry the $($script:failed.Count) that failed"
    $btnUpdate.Visibility = if ($idle -and $script:updatable.Count -gt 0) { 'Visible' } else { 'Collapsed' }
    $btnUpdate.Content = "Update $($script:updatable.Count) installed program(s)"
    $btnLog.Visibility = if ($idle -and $script:lastLog) { 'Visible' } else { 'Collapsed' }
    $btnWinget.Visibility = if (-not $script:hasWinget) { 'Visible' } else { 'Collapsed' }
}

function Mark-Installed($id) {
    foreach ($s in $script:sections) {
        foreach ($c in $s.Chips) {
            if ($c.Tag.Pkg.id -eq $id) {
                $c.Tag.Installed.Text = 'Installed on this PC'
                $c.Tag.Installed.Foreground = $bc.ConvertFromString('#E8FFD0')
                $c.Tag.Installed.Visibility = 'Visible'
            }
        }
    }
    $script:updatable = @($script:updatable | Where-Object { $_.id -ne $id })
}

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(300)
$timer.Add_Tick({
    $msg = $null
    while ($script:queue.TryDequeue([ref]$msg)) {
        $cut = $msg.IndexOf('|')
        $kind = $msg.Substring(0, $cut)
        $rest = $msg.Substring($cut + 1)
        switch ($kind) {
            'PROGRESS' {
                $pp = $rest.Split('|', 3)
                $bar.Value = ([int]$pp[0] - 1) / [double][int]$pp[1] * 100
                $status.Text = "Working on $($pp[0]) of $($pp[1]): $($pp[2])..."
            }
            'LOG' { $log.AppendText($rest + "`r`n"); $log.ScrollToEnd() }
            'OKID' { Mark-Installed $rest }
            'DONE' {
                $dd = $rest.Split('|', 4)
                $ok = [int]$dd[0]; $fail = [int]$dd[1]
                $failedIds = @($dd[2].Split(',') | Where-Object { $_ })
                $restart = $dd[3]
                $timer.Stop()
                Set-Busy $false
                $bar.Value = 100
                $btnCancel.Visibility = 'Collapsed'
                $script:failed = @($catalog | Where-Object { $failedIds -contains $_.id })
                Update-Counts
                Show-Actions
                $stopped = if ($script:state.Cancel) { ' (stopped early)' } else { '' }
                $status.Text = "Finished: $ok done or already up to date, $fail failed.$stopped"
                $text = "Done.`n`nInstalled, updated or already up to date: $ok`nFailed: $fail"
                if ($fail -gt 0) { $text += "`n`nThe reason for each failure is in the log. Use 'Retry' to try them again." }
                if ($restart) { $text += "`n`nRestart your PC to finish setting up: $restart" }
                if ($cfg.afterInstall -and $ok -gt 0) { $text += "`n`n$($cfg.afterInstall)" }
                if ($script:lastLog) { $text += "`n`nLog saved to:`n$($script:lastLog)" }
                if ($AutoTest) {
                    Set-Content -LiteralPath $ResultFile -Value @($status.Text, ('failed: ' + ($script:failed.name -join ', ')), ('retry button visible: ' + $btnRetry.Visibility), ('log button visible: ' + $btnLog.Visibility), ('log file: ' + $script:lastLog), '--- results box would say ---', $text) -Encoding UTF8
                    $win.Close()
                } else {
                    [void][Windows.MessageBox]::Show($win, $text, $cfg.title)
                }
            }
        }
    }
})

$btnCancel.Add_Click({ $script:state.Cancel = $true; $btnCancel.IsEnabled = $false; $status.Text = 'Stopping after the current program...' })

function Start-Run($pkgs, $action, $question) {
    $pkgs = @($pkgs)
    if ($pkgs.Count -eq 0) { return }
    if (-not $script:hasWinget) {
        [void][Windows.MessageBox]::Show($win, "Windows Package Manager (winget) was not found.`nGet 'App Installer' from the Microsoft Store, then try again.", $cfg.title, 'OK', 'Warning')
        return
    }
    if (-not $AutoTest) { if ([Windows.MessageBox]::Show($win, $question, $cfg.title, 'YesNo', 'Question') -ne 'Yes') { return } }

    # programs listed in "installFirst" go first, in that order (for example WSL before Docker)
    $first = @($cfg.installFirst)
    $ordered = @()
    for ($k = 0; $k -lt $pkgs.Count; $k++) {
        $idx = [array]::IndexOf($first, $pkgs[$k].id)
        $ordered += [pscustomobject]@{ P = $pkgs[$k]; K = $(if ($idx -ge 0) { $idx } else { 100000 + $k }) }
    }
    $items = @($ordered | Sort-Object K | ForEach-Object { $_.P })

    New-Item -ItemType Directory -Force $logDir | Out-Null
    $script:lastLog = Join-Path $logDir (($cfg.title -replace '[^A-Za-z0-9]+', '-') + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
    Set-Content -LiteralPath $script:lastLog -Value @("$($cfg.title) - $action - $(Get-Date)", "Programs: $($items.Count)", '') -Encoding UTF8

    $script:state.Cancel = $false
    $script:failed = @()
    Set-Busy $true
    $btnCancel.IsEnabled = $true
    $btnCancel.Visibility = 'Visible'
    Show-Actions
    $btnInstall.IsEnabled = $false
    $bar.Value = 0
    $bar.Visibility = 'Visible'
    $log.Clear()
    $log.Visibility = 'Visible'

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($script:worker.ToString()).AddArgument($items).AddArgument($script:queue).AddArgument($script:state).AddArgument($action).AddArgument($script:lastLog)
    $script:handle = $ps.BeginInvoke()
    $timer.Start()
}

$btnInstall.Add_Click({
    $picked = @()
    foreach ($s in $script:sections) { foreach ($c in $s.Chips) { if ($c.IsChecked) { $picked += $c.Tag.Pkg } } }
    Start-Run $picked 'install' "Download and install $($picked.Count) program(s)?`n`nThey install quietly in the background, in a sensible order. Some may ask for administrator permission."
})
$btnRetry.Add_Click({ Start-Run $script:failed 'install' "Try the $($script:failed.Count) failed program(s) again?" })
$btnUpdate.Add_Click({ Start-Run $script:updatable 'upgrade' "Update $($script:updatable.Count) program(s) that have a newer version?`n`nOnly programs from this list that are already on your PC are touched." })
$btnLog.Add_Click({ if ($script:lastLog -and (Test-Path $script:lastLog)) { Start-Process notepad.exe -ArgumentList ('"{0}"' -f $script:lastLog) } })
$btnWinget.Add_Click({ Start-Process 'ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1' })

# ---- save / load your picks --------------------------------------------------------
$btnSave.Add_Click({
    $ids = @()
    foreach ($s in $script:sections) { foreach ($c in $s.Chips) { if ($c.IsChecked) { $ids += $c.Tag.Pkg.id } } }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = 'My picks (*.json)|*.json'
    $dlg.FileName = (($cfg.title -replace '[^A-Za-z0-9]+', '-') + '-picks.json')
    if ($dlg.ShowDialog($win)) {
        [IO.File]::WriteAllText($dlg.FileName, (ConvertTo-Json -InputObject ([ordered]@{ title = $cfg.title; ids = @($ids) }) -Depth 3), (New-Object Text.UTF8Encoding $false))
        $status.Text = "Saved $($ids.Count) pick(s) to $($dlg.FileName)"
    }
})
$btnLoad.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'My picks (*.json)|*.json'
    if ($dlg.ShowDialog($win)) {
        try {
            $data = Get-Content -LiteralPath $dlg.FileName -Raw | ConvertFrom-Json
            $ids = @($data.ids)
            $n = 0; $missing = 0
            foreach ($s in $script:sections) { foreach ($c in $s.Chips) { $on = ($ids -contains $c.Tag.Pkg.id); $c.IsChecked = $on; Set-ChipLook $c; if ($on) { $n++ } } }
            $missing = $ids.Count - $n
            Update-Counts
            $status.Text = "Loaded $n pick(s)." + $(if ($missing -gt 0) { "  ($missing from the file are not in this list.)" } else { '' }) + '  ' + $status.Text
        } catch {
            [void][Windows.MessageBox]::Show($win, "That file could not be read as a list of picks.", $cfg.title, 'OK', 'Warning')
        }
    }
})
# ---- quick-pick buttons (add a ready-made group of programs to the selection) ----
if ($presets.Count -gt 0) {
    $presetRow.Visibility = 'Visible'
    foreach ($pr in $presets) {
        $b = New-Object Windows.Controls.Button
        $b.Content = $pr.name
        $b.Style = $win.FindResource('Pill')
        $b.Margin = '0,0,10,6'
        $b.ToolTip = "$($pr.tip)`n(adds these programs to your selection)"
        $b.Tag = $pr
        $b.Add_Click({
            $ids = @($this.Tag.ids)
            $n = 0
            foreach ($s in $script:sections) {
                foreach ($c in $s.Chips) {
                    if (($ids -contains $c.Tag.Pkg.id) -and -not $c.IsChecked) { $c.IsChecked = $true; Set-ChipLook $c; $n++ }
                }
            }
            Update-Counts
            $status.Text = "Added $n program(s) from '$($this.Tag.name)'.  " + $status.Text
        })
        [void]$presetRow.Children.Add($b)
    }
}
Update-Counts
if ($DemoSearch) { $search.Text = $DemoSearch }

Show-Actions
if (-not $SnapshotPath -and $script:hasWinget) {
    # Quietly look (read-only) at what is already installed, then at which of those have updates.
    $script:listResult = [hashtable]::Synchronized(@{ Done = $false; Text = '' })
    $script:upgResult = [hashtable]::Synchronized(@{ Done = $false; Text = '' })
    $script:detectStage = 1
    $lrs = [runspacefactory]::CreateRunspace(); $lrs.Open()
    $lps = [powershell]::Create(); $lps.Runspace = $lrs
    [void]$lps.AddScript({
        param($r)
        try { $r.Text = (& winget list --accept-source-agreements --disable-interactivity 2>&1 | Out-String) } catch { $r.Text = '' }
        $r.Done = $true
    }).AddArgument($script:listResult)
    [void]$lps.BeginInvoke()
    $detect = New-Object Windows.Threading.DispatcherTimer
    $detect.Interval = [TimeSpan]::FromSeconds(1)
    $detect.Add_Tick({
        if ($script:detectStage -eq 1 -and $script:listResult.Done) {
            $text = $script:listResult.Text
            foreach ($s in $script:sections) {
                foreach ($c in $s.Chips) {
                    if ($text.IndexOf($c.Tag.Pkg.id, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $c.Tag.Installed.Visibility = 'Visible' }
                }
            }
            $script:detectStage = 2
            $urs = [runspacefactory]::CreateRunspace(); $urs.Open()
            $ups = [powershell]::Create(); $ups.Runspace = $urs
            [void]$ups.AddScript({
                param($r)
                try { $r.Text = (& winget upgrade --accept-source-agreements --disable-interactivity 2>&1 | Out-String) } catch { $r.Text = '' }
                $r.Done = $true
            }).AddArgument($script:upgResult)
            [void]$ups.BeginInvoke()
        }
        elseif ($script:detectStage -eq 2 -and $script:upgResult.Done) {
            $detect.Stop()
            $text = $script:upgResult.Text
            $found = @()
            foreach ($s in $script:sections) {
                foreach ($c in $s.Chips) {
                    $installed = ($c.Tag.Installed.Visibility -eq 'Visible')
                    if ($installed -and $text.IndexOf($c.Tag.Pkg.id, [StringComparison]::OrdinalIgnoreCase) -ge 0 -and $c.Tag.Pkg.source -ne 'msstore') {
                        $c.Tag.Installed.Text = 'Update available'
                        $c.Tag.Installed.Foreground = $bc.ConvertFromString('#FFE066')
                        $found += $c.Tag.Pkg
                    }
                }
            }
            $script:updatable = @($found)
            Show-Actions
        }
    })
    $detect.Start()
}
# ---- off-screen preview mode (used to check the layout without showing a window) ----
if ($SnapshotPath) {
    $win.WindowStartupLocation = 'Manual'
    $win.Left = -6000
    $win.Top = 0
    $win.ShowInTaskbar = $false
    $win.Add_ContentRendered({
        $win.Dispatcher.BeginInvoke([Action]{
            $w = [int]$win.ActualWidth; $h = [int]$win.ActualHeight
            $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
            $rtb.Render($win)
            $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
            [void]$enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
            $fs = [IO.File]::Create($SnapshotPath)
            $enc.Save($fs); $fs.Close()
            $win.Close()
        }, [Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
    })
}

if ($AutoTest) {
    $win.WindowStartupLocation = 'Manual'; $win.Left = -6000; $win.Top = 0; $win.ShowInTaskbar = $false
    $InstallIds = @($InstallIds | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
    $win.Add_ContentRendered({
        $win.Dispatcher.BeginInvoke([Action]{
            $picked = @()
            foreach ($s in $script:sections) { foreach ($c in $s.Chips) { $c.IsChecked = ($InstallIds -contains $c.Tag.Pkg.id); Set-ChipLook $c; if ($c.IsChecked) { $picked += $c.Tag.Pkg } } }
            Update-Counts
            Start-Run $picked 'install' ''
        }, [Windows.Threading.DispatcherPriority]::ApplicationIdle) | Out-Null
    })
}
[void]$win.ShowDialog()
