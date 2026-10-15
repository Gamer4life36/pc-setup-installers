param([string]$Config = 'gamer.config.json', [string]$SnapshotPath = '', [string]$DemoSearch = '')

# Shared installer window (cartoon style) around winget. Which programs it shows comes from a config file.
# Nothing is installed until you press "Install selected" and confirm.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cfgPath = if ([IO.Path]::IsPathRooted($Config)) { $Config } else { Join-Path $here $Config }
$cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
$catalog = Get-Content (Join-Path $here $cfg.catalog) -Raw | ConvertFrom-Json
$iconFile = Join-Path $here $cfg.icons
$iconDir = if ($cfg.iconDir) { $cfg.iconDir } else { 'icons' }
$presetFile = if ($cfg.presets) { Join-Path $here $cfg.presets } else { $null }
$presets = if ($presetFile -and (Test-Path $presetFile)) { @(Get-Content $presetFile -Raw | ConvertFrom-Json) } else { @() }
$icons = if (Test-Path $iconFile) { Get-Content $iconFile -Raw | ConvertFrom-Json } else { $null }
$tick = [string][char]0x2714
$cross = [string][char]0x2716

# Programs ticked (green) when the window opens. Everything else starts red.
$starter = @($cfg.starter)

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
      <StackPanel Orientation="Horizontal">
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
      </StackPanel>
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
          <Button x:Name="BtnCancel" Content="Stop after this program" Style="{StaticResource Pill}" Visibility="Collapsed" HorizontalAlignment="Left" Margin="0,10,0,0"/>
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
    $btnInstall.IsEnabled = ($total -gt 0 -and -not $script:installing)
    if (-not $script:installing) {
        $status.Text = if ($total -eq 0) { 'Pick at least one program to install.' } else { "$total program(s) will be installed." }
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

# ---- installing -------------------------------------------------------------
$script:queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(300)
$timer.Add_Tick({
    $msg = $null
    while ($script:queue.TryDequeue([ref]$msg)) {
        $parts = $msg.Split('|', 4)
        switch ($parts[0]) {
            'PROGRESS' {
                $bar.Value = ([int]$parts[1] - 1) / [double][int]$parts[2] * 100
                $status.Text = "Installing $($parts[1]) of $($parts[2]): $($parts[3])..."
            }
            'LOG' { $log.AppendText($parts[1] + "`r`n"); $log.ScrollToEnd() }
            'DONE' {
                $timer.Stop()
                $script:installing = $false
                $bar.Value = 100
                $btnCancel.Visibility = 'Collapsed'
                foreach ($s in $script:sections) { foreach ($c in $s.Chips) { $c.IsEnabled = $true } }
                Update-Counts
                $status.Text = "Finished: $($parts[1]) installed or already present, $($parts[2]) failed." + $(if ($script:state.Cancel) { ' (stopped early)' } else { '' })
                [void][Windows.MessageBox]::Show($win, "Done.`n`nInstalled or already present: $($parts[1])`nFailed: $($parts[2])`n`nThe log in the window shows details.", $cfg.title)
            }
        }
    }
})

$btnCancel.Add_Click({ $script:state.Cancel = $true; $btnCancel.IsEnabled = $false; $status.Text = 'Stopping after the current program...' })

$btnInstall.Add_Click({
    $picked = @()
    foreach ($s in $script:sections) { foreach ($c in $s.Chips) { if ($c.IsChecked) { $picked += $c.Tag.Pkg } } }
    if ($picked.Count -eq 0) { return }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        [void][Windows.MessageBox]::Show($win, "Windows Package Manager (winget) was not found.`nInstall 'App Installer' from the Microsoft Store, then try again.", $cfg.title, 'OK', 'Warning')
        return
    }
    $answer = [Windows.MessageBox]::Show($win, "Download and install $($picked.Count) program(s)?`n`nThey install quietly in the background. Some may ask for administrator permission.", $cfg.title, 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }

    $script:installing = $true
    $script:state.Cancel = $false
    $btnCancel.IsEnabled = $true
    $btnCancel.Visibility = 'Visible'
    foreach ($s in $script:sections) { foreach ($c in $s.Chips) { $c.IsEnabled = $false } }
    $btnInstall.IsEnabled = $false
    $bar.Value = 0
    $bar.Visibility = 'Visible'
    $log.Clear()
    $log.Visibility = 'Visible'

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        param($items, $q, $state)
        $i = 0; $ok = 0; $fail = 0
        foreach ($p in $items) {
            if ($state.Cancel) { break }
            $i++
            $q.Enqueue("PROGRESS|$i|$($items.Count)|$($p.name)")
            $a = @('install', '--id', $p.id, '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
            if ($p.source -eq 'msstore') { $a += @('--source', 'msstore') }
            try { & winget @a *> $null; $code = $LASTEXITCODE } catch { $code = 1 }
            if ($code -eq 0) { $ok++; $q.Enqueue("LOG|OK       $($p.name)") }
            elseif ($code -eq -1978335189) { $ok++; $q.Enqueue("LOG|ALREADY  $($p.name) (already installed)") }
            else { $fail++; $q.Enqueue("LOG|FAILED   $($p.name) (code $code)") }
        }
        $q.Enqueue("DONE|$ok|$fail")
    }).AddArgument($picked).AddArgument($script:queue).AddArgument($script:state)
    $script:handle = $ps.BeginInvoke()
    $timer.Start()
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

if (-not $SnapshotPath -and (Get-Command winget -ErrorAction SilentlyContinue)) {
    $script:listResult = [hashtable]::Synchronized(@{ Done = $false; Text = '' })
    $lrs = [runspacefactory]::CreateRunspace()
    $lrs.Open()
    $lps = [powershell]::Create()
    $lps.Runspace = $lrs
    [void]$lps.AddScript({
        param($r)
        try { $r.Text = (& winget list --accept-source-agreements --disable-interactivity 2>&1 | Out-String) } catch { $r.Text = '' }
        $r.Done = $true
    }).AddArgument($script:listResult)
    [void]$lps.BeginInvoke()
    $detect = New-Object Windows.Threading.DispatcherTimer
    $detect.Interval = [TimeSpan]::FromSeconds(1)
    $detect.Add_Tick({
        if ($script:listResult.Done) {
            $detect.Stop()
            $text = $script:listResult.Text
            foreach ($s in $script:sections) {
                foreach ($c in $s.Chips) {
                    if ($text.IndexOf($c.Tag.Pkg.id, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $c.Tag.Installed.Visibility = 'Visible' }
                }
            }
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

[void]$win.ShowDialog()
