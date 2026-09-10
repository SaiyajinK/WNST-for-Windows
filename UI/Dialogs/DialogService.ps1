function Show-AccentPicker {
    param([string]$InitialColor,[Windows.Window]$OwnerWindow=$null)
    $initial = ConvertTo-AccentHex $InitialColor; if (-not $initial) { $initial = '#1A9FFF' }
    $pickerAccent = ConvertTo-AccentHex ([string]$script:Settings.AccentColor); if (-not $pickerAccent) { $pickerAccent = '#1A9FFF' }
    $pickerBackground = Get-AppThemeColor 'WindowBrush' '#20242B'; $pickerCard = Get-AppThemeColor 'CardBrush' '#171A1F'; $pickerInput = Get-AppThemeColor 'InputBrush' '#111318'; $pickerText = Get-AppThemeColor 'TextBrush' '#F4F4F4'; $pickerMuted = Get-AppThemeColor 'MutedBrush' '#A8ADB5'; $pickerBorder = Get-AppThemeColor 'CardBorderBrush' '#3B414A'
    [xml]$pickerXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="470" Height="390" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" Foreground="$pickerText" FontFamily="Segoe UI Variable Text"><Window.Resources><Style TargetType="TextBox"><Setter Property="Height" Value="34"/><Setter Property="Padding" Value="8,5"/><Setter Property="Foreground" Value="$pickerText"/><Setter Property="Background" Value="$pickerInput"/><Setter Property="BorderBrush" Value="$pickerBorder"/><Setter Property="CaretBrush" Value="$pickerText"/><Setter Property="VerticalContentAlignment" Value="Center"/></Style><Style x:Key="PickerButton" TargetType="Button"><Setter Property="Height" Value="32"/><Setter Property="Padding" Value="12,4"/><Setter Property="Foreground" Value="$pickerText"/><Setter Property="Background" Value="$pickerCard"/><Setter Property="BorderBrush" Value="$pickerBorder"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="$pickerAccent"/><Setter TargetName="B" Property="BorderBrush" Value="$pickerAccent"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style></Window.Resources><Border Background="$pickerBackground" BorderBrush="$pickerBorder" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))"><Grid><Grid.RowDefinitions><RowDefinition Height="42"/><RowDefinition Height="*"/></Grid.RowDefinitions><Border Grid.Row="0" Background="$pickerCard" CornerRadius="$([int](Get-AppCornerRadiusValue)),$([int](Get-AppCornerRadiusValue)),0,0"><Grid x:Name="PickerTitleBar"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="34"/></Grid.ColumnDefinitions><TextBlock x:Name="PickerTitle" Margin="14,0" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold"/><Button x:Name="PickerClose" Grid.Column="1" Style="{StaticResource PickerButton}" Content="×" Padding="0" Height="28" Width="28"/></Grid></Border><Grid Grid.Row="1" Margin="14"><Grid.RowDefinitions><RowDefinition Height="76"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><Border x:Name="PickerPreview" CornerRadius="$([int](Get-AppCornerRadiusValue))" BorderBrush="$pickerBorder" BorderThickness="1"/><Grid Grid.Row="1" Margin="0,10,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="58"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="HEX" VerticalAlignment="Center" Foreground="$pickerMuted"/><TextBox x:Name="PickerHex" Grid.Column="1" MaxLength="7"/></Grid><Grid Grid.Row="2" Margin="0,0,0,10"><Grid.ColumnDefinitions><ColumnDefinition Width="58"/><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/><ColumnDefinition Width="8"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><TextBlock Text="RGB" VerticalAlignment="Center" Foreground="$pickerMuted"/><TextBox x:Name="PickerR" Grid.Column="1" MaxLength="3"/><TextBox x:Name="PickerG" Grid.Column="3" MaxLength="3"/><TextBox x:Name="PickerB" Grid.Column="5" MaxLength="3"/></Grid><UniformGrid x:Name="PickerSwatches" Grid.Row="3" Rows="2" Columns="10" Margin="0,0,0,10"/><Grid Grid.Row="4"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="8"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock x:Name="PickerError" Foreground="#FF6B72" VerticalAlignment="Center"/><Button x:Name="PickerCancel" Grid.Column="1" Style="{StaticResource PickerButton}"/><Button x:Name="PickerApply" Grid.Column="3" Style="{StaticResource PickerButton}"/></Grid></Grid></Grid></Border></Window>
"@
    $reader = New-Object Xml.XmlNodeReader($pickerXaml); $dialog = [Windows.Markup.XamlReader]::Load($reader); $pickerOwner = if ($OwnerWindow) { $OwnerWindow } else { $window }; $dialog.Owner = $pickerOwner; $dialog.FontFamily = $script:UiFontFamily; Enable-RoundedDialogFrame $dialog
    $titleBar=$dialog.FindName('PickerTitleBar'); $title=$dialog.FindName('PickerTitle'); $close=$dialog.FindName('PickerClose'); $hexBox=$dialog.FindName('PickerHex'); $rBox=$dialog.FindName('PickerR'); $gBox=$dialog.FindName('PickerG'); $bBox=$dialog.FindName('PickerB'); $preview=$dialog.FindName('PickerPreview'); $swatches=$dialog.FindName('PickerSwatches'); $errorText=$dialog.FindName('PickerError'); $cancel=$dialog.FindName('PickerCancel'); $apply=$dialog.FindName('PickerApply')
    $dialog.Content.Margin=[Windows.Thickness]::new(1)
    if ($titleBar.ColumnDefinitions.Count -eq 2) { $rightInset=New-Object Windows.Controls.ColumnDefinition; $rightInset.Width=[Windows.GridLength]::new(8); [void]$titleBar.ColumnDefinitions.Add($rightInset) }
    Set-DialogCloseButtonAppearance -Button $close -ForegroundColor $pickerText
    Set-RoundedTextBoxTemplate -TextBoxes @($hexBox,$rBox,$gBox,$bBox)
    foreach($pickerTextBox in @($hexBox,$rBox,$gBox,$bBox)){ $pickerTextBox.Padding='8,3' }
    $title.Text=T 'AccentPickerTitle'; $cancel.Content=T 'Cancel'; $apply.Content=T 'Apply'; $state=[pscustomobject]@{Updating=$false;Selected=$initial}
    $setPickerColor = { param([string]$Hex) $normalized=ConvertTo-AccentHex $Hex; if(-not $normalized){return}; $state.Updating=$true; try{$state.Selected=$normalized;$hexBox.Text=$normalized;$rBox.Text=[Convert]::ToInt32($normalized.Substring(1,2),16);$gBox.Text=[Convert]::ToInt32($normalized.Substring(3,2),16);$bBox.Text=[Convert]::ToInt32($normalized.Substring(5,2),16);$preview.Background=New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($normalized));$errorText.Text=''}finally{$state.Updating=$false} }
    foreach($color in @('#1A9FFF','#0078D4','#005FB8','#7A5AF8','#C239B3','#E3008C','#D13438','#FF8C00','#F9D71C','#16A085','#00A86B','#2E8B57','#20B2AA','#607D8B','#6B7280','#222222','#FFFFFF','#FF6B6B','#4CC38A','#60CDFF')){$button=New-Object Windows.Controls.Button;$button.Tag=$color;$button.Margin='3';$button.Height=28;$button.ToolTip=$color;$button.BorderThickness=1;$button.BorderBrush=New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($pickerBorder));$button.Background=New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($color));$button.Add_Click({param($sender,$eventArgs)& $setPickerColor ([string]$sender.Tag)});[void]$swatches.Children.Add($button)}
    $hexBox.Add_TextChanged({if(-not $state.Updating){$value=ConvertTo-AccentHex $hexBox.Text;if($value){& $setPickerColor $value}}});$rgbChanged={if(-not $state.Updating){$value=ConvertTo-AccentHex ("{0},{1},{2}" -f $rBox.Text,$gBox.Text,$bBox.Text);if($value){& $setPickerColor $value}}};$rBox.Add_TextChanged($rgbChanged);$gBox.Add_TextChanged($rgbChanged);$bBox.Add_TextChanged($rgbChanged)
    $titleBar.Add_MouseLeftButtonDown({try{$dialog.DragMove()}catch{}});$close.Add_Click({$dialog.DialogResult=$false;$dialog.Close()});$cancel.Add_Click({$dialog.DialogResult=$false;$dialog.Close()});$apply.Add_Click({$value=ConvertTo-AccentHex $hexBox.Text;if(-not $value){$errorText.Text=T 'InvalidAccentColor';return};$dialog.Tag=$value;$dialog.DialogResult=$true;$dialog.Close()});& $setPickerColor $initial
    if($dialog.ShowDialog() -eq $true){return [string]$dialog.Tag};return $null
}

function Show-ManualEntryDialog {
    $dialogBackground = Get-AppThemeColor 'WindowBrush' '#20242B'
    $dialogSurface = Get-AppThemeColor 'CardBrush' '#171A1F'
    $dialogInput = Get-AppThemeColor 'InputBrush' '#111318'
    $dialogText = Get-AppThemeColor 'TextBrush' '#F4F4F4'
    $dialogMuted = Get-AppThemeColor 'MutedBrush' '#A8ADB5'
    $dialogBorder = Get-AppThemeColor 'CardBorderBrush' '#3B414A'
    $dialogAccent = ConvertTo-AccentHex ([string]$script:Settings.AccentColor)
    if (-not $dialogAccent) { $dialogAccent = '#1A9FFF' }
    [xml]$manualXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework" Width="620" MinWidth="500" Height="430" MinHeight="330" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="CanResize" AllowsTransparency="True" Background="Transparent" Foreground="$dialogText">
  <shell:WindowChrome.WindowChrome><shell:WindowChrome CaptionHeight="0" ResizeBorderThickness="6" CornerRadius="$([int](Get-AppCornerRadiusValue))" GlassFrameThickness="0" UseAeroCaptionButtons="False"/></shell:WindowChrome.WindowChrome>
  <Window.Resources>
    <Style x:Key="DialogButton" TargetType="Button">
      <Setter Property="Height" Value="32"/><Setter Property="Padding" Value="12,4"/><Setter Property="Foreground" Value="$dialogText"/><Setter Property="Background" Value="$dialogSurface"/><Setter Property="BorderBrush" Value="$dialogBorder"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="$dialogAccent"/><Setter TargetName="B" Property="BorderBrush" Value="$dialogAccent"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger><MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="Close"/></MultiTrigger.Conditions><Setter TargetName="B" Property="Background" Value="#D13438"/><Setter TargetName="B" Property="BorderBrush" Value="#D13438"/><Setter Property="Foreground" Value="#FFFFFF"/></MultiTrigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="B" Property="Opacity" Value="0.78"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="B" Property="Opacity" Value="0.42"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Border Margin="1" Background="$dialogBackground" BorderBrush="$dialogBorder" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))">
    <Grid><Grid.RowDefinitions><RowDefinition Height="42"/><RowDefinition Height="*"/></Grid.RowDefinitions>
      <Border x:Name="ManualTitleBar" Background="$dialogSurface" CornerRadius="$([int](Get-AppCornerRadiusValue)),$([int](Get-AppCornerRadiusValue)),0,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="34"/><ColumnDefinition Width="8"/></Grid.ColumnDefinitions><TextBlock x:Name="ManualTitle" Margin="12,0" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold"/><Button x:Name="ManualClose" Grid.Column="1" Style="{StaticResource DialogButton}" Tag="Close" Content="×" Padding="0" Width="28" Height="28"/></Grid></Border>
      <Grid Grid.Row="1" Margin="14"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock x:Name="ManualHint" Foreground="$dialogMuted" TextWrapping="Wrap" Margin="0,0,0,10"/>
        <Grid Grid.Row="1"><Border Background="$dialogInput" BorderBrush="$dialogBorder" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))"/><TextBox x:Name="ManualEditor" Margin="1" Padding="10" AcceptsReturn="True" AcceptsTab="False" TextWrapping="NoWrap" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto" Background="Transparent" BorderThickness="0" Foreground="$dialogText" CaretBrush="$dialogText" FontFamily="Consolas" FontSize="12" VerticalContentAlignment="Top"/><TextBlock x:Name="ManualExample" Margin="12,10" Foreground="$dialogMuted" FontFamily="Consolas" FontSize="12" TextWrapping="Wrap" IsHitTestVisible="False"/></Grid>
        <Grid Grid.Row="2" Margin="0,10,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="8"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock x:Name="ManualValidation" Foreground="$dialogMuted" VerticalAlignment="Center" TextWrapping="Wrap" Margin="0,0,12,0"/><Button x:Name="ManualCancel" Grid.Column="1" Style="{StaticResource DialogButton}"/><Button x:Name="ManualApply" Grid.Column="3" Style="{StaticResource DialogButton}" IsEnabled="False"/></Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
"@
    $reader = New-Object Xml.XmlNodeReader($manualXaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    $dialog.Owner = $window
    $dialog.FontFamily = $script:UiFontFamily
    Enable-RoundedDialogFrame $dialog
    $titleBar=$dialog.FindName('ManualTitleBar'); $title=$dialog.FindName('ManualTitle'); $close=$dialog.FindName('ManualClose'); $hint=$dialog.FindName('ManualHint'); $editor=$dialog.FindName('ManualEditor'); $example=$dialog.FindName('ManualExample'); $validationText=$dialog.FindName('ManualValidation'); $cancel=$dialog.FindName('ManualCancel'); $apply=$dialog.FindName('ManualApply')
    Set-DialogCloseButtonAppearance -Button $close -ForegroundColor $dialogText
    $title.Text=T 'ManualDialogTitle'; $hint.Text=T 'ManualDialogHint'; $example.Text=T 'ManualExample'; $cancel.Content=T 'Cancel'; $apply.Content=T 'AddToHosts'
    $validationState = [pscustomobject]@{ IsValid=$false; EntryCount=0 }
    $validateManualContent = {
        $example.Visibility = if ([string]::IsNullOrWhiteSpace($editor.Text)) { 'Visible' } else { 'Collapsed' }
        if ([string]::IsNullOrWhiteSpace($editor.Text)) {
            $validationState.IsValid=$false; $validationState.EntryCount=0; $validationText.Text=''; $validationText.Foreground=$dialogMuted; $apply.IsEnabled=$false
            return
        }
        $result = Test-HuManualHostsEntries -Content $editor.Text
        $validationState.IsValid=[bool]$result.IsValid; $validationState.EntryCount=[int]$result.EntryCount; $apply.IsEnabled=[bool]$result.IsValid
        if ($result.IsValid) { $validationText.Text=TF 'ManualFormatValid' @($result.EntryCount); $validationText.Foreground='#4CC38A' }
        else { $validationText.Text=TF 'ManualFormatInvalid' @($result.ErrorMessage); $validationText.Foreground='#D13438' }
    }
    $editor.Add_TextChanged({ & $validateManualContent })
    $titleBar.Add_MouseLeftButtonDown({ try { $dialog.DragMove() } catch { } })
    $close.Add_Click({ $dialog.DialogResult=$false; $dialog.Close() })
    $cancel.Add_Click({ $dialog.DialogResult=$false; $dialog.Close() })
    $apply.Add_Click({ & $validateManualContent; if (-not $validationState.IsValid) { return }; $dialog.Tag=$editor.Text; $dialog.DialogResult=$true; $dialog.Close() })
    $dialog.Add_ContentRendered({ $editor.Focus() | Out-Null })
    if ($dialog.ShowDialog() -eq $true) { return [string]$dialog.Tag }
    return $null
}

function Show-AppMessageDialog {
    param([Parameter(Mandatory=$true)][string]$Message, [Parameter(Mandatory=$true)][string]$Title, [ValidateSet('Info','Error')][string]$Kind='Info')
    $dialogBackground = Get-AppThemeColor 'WindowBrush' '#20242B'
    $dialogSurface = Get-AppThemeColor 'CardBrush' '#171A1F'
    $dialogText = Get-AppThemeColor 'TextBrush' '#F4F4F4'
    $dialogMuted = Get-AppThemeColor 'MutedBrush' '#A8ADB5'
    $dialogBorder = Get-AppThemeColor 'WindowBorderBrush' '#59616B'
    $dialogAccent = ConvertTo-AccentHex ([string]$script:Settings.AccentColor)
    if (-not $dialogAccent) { $dialogAccent = '#1A9FFF' }
    $dialogIndicator = if ($Kind -eq 'Error') { '#D13438' } else { $dialogAccent }
    [xml]$messageXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="460" Height="205" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" Foreground="$dialogText">
  <Window.Resources><Style x:Key="MessageButtonStyle" TargetType="Button"><Setter Property="Height" Value="32"/><Setter Property="MinWidth" Value="92"/><Setter Property="Padding" Value="12,4"/><Setter Property="Foreground" Value="$dialogText"/><Setter Property="Background" Value="$dialogSurface"/><Setter Property="BorderBrush" Value="$dialogBorder"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="$dialogAccent"/><Setter TargetName="B" Property="BorderBrush" Value="$dialogAccent"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger><MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="Close"/></MultiTrigger.Conditions><Setter TargetName="B" Property="Background" Value="#D13438"/><Setter TargetName="B" Property="BorderBrush" Value="#D13438"/><Setter Property="Foreground" Value="#FFFFFF"/></MultiTrigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style></Window.Resources>
  <Border Margin="1" Background="$dialogBackground" BorderBrush="$dialogBorder" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))"><Grid><Grid.RowDefinitions><RowDefinition Height="42"/><RowDefinition Height="*"/></Grid.RowDefinitions><Border x:Name="MessageTitleBar" Background="$dialogSurface" CornerRadius="$([int](Get-AppCornerRadiusValue)),$([int](Get-AppCornerRadiusValue)),0,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="34"/><ColumnDefinition Width="8"/></Grid.ColumnDefinitions><TextBlock x:Name="MessageTitle" Margin="12,0" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold"/><Button x:Name="MessageClose" Grid.Column="1" Style="{StaticResource MessageButtonStyle}" Tag="Close" Content="×" Padding="0" MinWidth="0" Width="28" Height="28"/></Grid></Border><Grid Grid.Row="1" Margin="16,14"><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="12"/><ColumnDefinition Width="12"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Ellipse Width="9" Height="9" Fill="$dialogIndicator" VerticalAlignment="Top" Margin="0,4,0,0"/><TextBlock x:Name="MessageText" Grid.Column="2" Foreground="$dialogMuted" TextWrapping="Wrap" VerticalAlignment="Top"/></Grid><Button x:Name="MessageDone" Grid.Row="1" HorizontalAlignment="Right" Style="{StaticResource MessageButtonStyle}" IsCancel="True"/></Grid></Grid></Border>
</Window>
"@
    $reader=New-Object Xml.XmlNodeReader($messageXaml); $dialog=[Windows.Markup.XamlReader]::Load($reader); $dialog.Owner=$window; $dialog.FontFamily=$script:UiFontFamily; Enable-RoundedDialogFrame $dialog
    $titleBar=$dialog.FindName('MessageTitleBar'); $titleText=$dialog.FindName('MessageTitle'); $messageText=$dialog.FindName('MessageText'); $close=$dialog.FindName('MessageClose'); $done=$dialog.FindName('MessageDone')
    Set-DialogCloseButtonAppearance -Button $close -ForegroundColor $dialogText
    $titleText.Text=$Title; $messageText.Text=$Message; $done.Content=T 'Close'
    $titleBar.Add_MouseLeftButtonDown({try{$dialog.DragMove()}catch{}}); $close.Add_Click({$dialog.Close()}); $done.Add_Click({$dialog.Close()})
    [void]$dialog.ShowDialog()
}

function Show-AppError { param([string]$Message) Show-AppMessageDialog -Message $Message -Title (T 'ErrorTitle') -Kind Error }

function Show-AppInfo { param([string]$Message) Show-AppMessageDialog -Message $Message -Title (T 'OperationSuccess') -Kind Info }

function Show-HuStoreChoiceDialog {
    $dialogBackground=Get-AppThemeColor 'WindowBrush' '#20242B'; $dialogSurface=Get-AppThemeColor 'CardBrush' '#171A1F'; $dialogText=Get-AppThemeColor 'TextBrush' '#F4F4F4'; $dialogMuted=Get-AppThemeColor 'MutedBrush' '#A8ADB5'; $dialogBorder=Get-AppThemeColor 'WindowBorderBrush' '#59616B'; $dialogAccent=ConvertTo-AccentHex ([string]$script:Settings.AccentColor); if(-not $dialogAccent){$dialogAccent='#1A9FFF'}
    [xml]$choiceXaml=@"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="510" Height="220" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" Foreground="$dialogText">
  <Window.Resources><Style x:Key="ChoiceButtonStyle" TargetType="Button"><Setter Property="Height" Value="34"/><Setter Property="MinWidth" Value="126"/><Setter Property="Padding" Value="12,4"/><Setter Property="Foreground" Value="$dialogText"/><Setter Property="Background" Value="$dialogSurface"/><Setter Property="BorderBrush" Value="$dialogBorder"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="$dialogAccent"/><Setter TargetName="B" Property="BorderBrush" Value="$dialogAccent"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style></Window.Resources>
  <Border Margin="1" Background="$dialogBackground" BorderBrush="$dialogBorder" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))"><Grid><Grid.RowDefinitions><RowDefinition Height="42"/><RowDefinition Height="*"/></Grid.RowDefinitions><Border x:Name="ChoiceTitleBar" Background="$dialogSurface" CornerRadius="$([int](Get-AppCornerRadiusValue)),$([int](Get-AppCornerRadiusValue)),0,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="36"/></Grid.ColumnDefinitions><TextBlock x:Name="ChoiceTitle" Margin="13,0" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold"/><Button x:Name="ChoiceClose" Grid.Column="1" Style="{StaticResource ChoiceButtonStyle}" Content="×" Padding="0" MinWidth="0" Width="28" Height="28"/></Grid></Border><Grid Grid.Row="1" Margin="16,14"><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock x:Name="ChoiceMessage" Foreground="$dialogMuted" TextWrapping="Wrap" VerticalAlignment="Center" FontSize="12"/><StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0"><Button x:Name="ChoiceBrowser" Style="{StaticResource ChoiceButtonStyle}"/><Button x:Name="ChoiceStore" Style="{StaticResource ChoiceButtonStyle}" Margin="8,0,0,0"/></StackPanel></Grid></Grid></Border>
</Window>
"@
    $reader=New-Object Xml.XmlNodeReader($choiceXaml); $dialog=[Windows.Markup.XamlReader]::Load($reader); $dialog.Owner=$window; $dialog.FontFamily=$script:UiFontFamily; Enable-RoundedDialogFrame $dialog
    $titleBar=$dialog.FindName('ChoiceTitleBar'); $title=$dialog.FindName('ChoiceTitle'); $message=$dialog.FindName('ChoiceMessage'); $close=$dialog.FindName('ChoiceClose'); $browser=$dialog.FindName('ChoiceBrowser'); $store=$dialog.FindName('ChoiceStore')
    $title.Text=T 'MicrosoftStore'; $message.Text=T 'StoreOpenQuestion'; $browser.Content=T 'ExternalBrowser'; $store.Content=T 'MicrosoftStore'
    $titleBar.Add_MouseLeftButtonDown({try{$dialog.DragMove()}catch{}}); $close.Add_Click({$dialog.Tag='Cancel';$dialog.Close()}); $browser.Add_Click({$dialog.Tag='Browser';$dialog.DialogResult=$true;$dialog.Close()}); $store.Add_Click({$dialog.Tag='Store';$dialog.DialogResult=$true;$dialog.Close()})
    [void]$dialog.ShowDialog(); return [string]$dialog.Tag
}


function Show-AppConfirm {
    param([string]$Message)
    $dialogBackground = Get-AppThemeColor 'WindowBrush' '#20242B'
    $dialogSurface = Get-AppThemeColor 'CardBrush' '#171A1F'
    $dialogText = Get-AppThemeColor 'TextBrush' '#F4F4F4'
    $dialogMuted = Get-AppThemeColor 'MutedBrush' '#A8ADB5'
    $dialogBorder = Get-AppThemeColor 'WindowBorderBrush' '#59616B'
    $dialogAccent = ConvertTo-AccentHex ([string]$script:Settings.AccentColor)
    if (-not $dialogAccent) { $dialogAccent = '#1A9FFF' }
    $dialogHeight = if ($Message.Length -gt 380) { 330 } elseif ($Message.Length -gt 220) { 260 } else { 205 }
    [xml]$confirmXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="460" Height="$dialogHeight" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" Foreground="$dialogText" FontFamily="Segoe UI Variable Text">
  <Window.Resources>
    <Style x:Key="ConfirmButtonStyle" TargetType="Button">
      <Setter Property="Height" Value="32"/><Setter Property="MinWidth" Value="92"/><Setter Property="Padding" Value="12,4"/><Setter Property="Foreground" Value="$dialogText"/><Setter Property="Background" Value="$dialogSurface"/><Setter Property="BorderBrush" Value="$dialogBorder"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="$dialogAccent"/><Setter TargetName="B" Property="BorderBrush" Value="$dialogAccent"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger><MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="Close"/></MultiTrigger.Conditions><Setter TargetName="B" Property="Background" Value="#D13438"/><Setter TargetName="B" Property="BorderBrush" Value="#D13438"/><Setter Property="Foreground" Value="#FFFFFF"/></MultiTrigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Border Margin="1" Background="$dialogBackground" BorderBrush="$dialogBorder" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))">
    <Grid><Grid.RowDefinitions><RowDefinition Height="42"/><RowDefinition Height="*"/></Grid.RowDefinitions>
      <Border x:Name="ConfirmTitleBar" Background="$dialogSurface" CornerRadius="$([int](Get-AppCornerRadiusValue)),$([int](Get-AppCornerRadiusValue)),0,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="34"/><ColumnDefinition Width="8"/></Grid.ColumnDefinitions><TextBlock x:Name="ConfirmTitleText" Margin="12,0" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold"/><Button x:Name="ConfirmClose" Grid.Column="1" Style="{StaticResource ConfirmButtonStyle}" Tag="Close" Content="×" Padding="0" MinWidth="0" Width="28" Height="28"/></Grid></Border>
      <Grid Grid.Row="1" Margin="16,14,16,14"><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock x:Name="ConfirmMessage" Foreground="$dialogMuted" TextWrapping="Wrap" VerticalAlignment="Center" FontSize="12"/><StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0"><Button x:Name="ConfirmCancel" Style="{StaticResource ConfirmButtonStyle}" IsCancel="True"/><Button x:Name="ConfirmAccept" Style="{StaticResource ConfirmButtonStyle}" IsDefault="True" Margin="8,0,0,0"/></StackPanel></Grid>
    </Grid>
  </Border>
</Window>
"@
    $reader = New-Object Xml.XmlNodeReader($confirmXaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    $dialog.Owner = $window
    $dialog.FontFamily = $script:UiFontFamily
    Enable-RoundedDialogFrame $dialog
    $titleBar = $dialog.FindName('ConfirmTitleBar'); $title = $dialog.FindName('ConfirmTitleText'); $messageText = $dialog.FindName('ConfirmMessage'); $close = $dialog.FindName('ConfirmClose'); $cancel = $dialog.FindName('ConfirmCancel'); $accept = $dialog.FindName('ConfirmAccept')
    Set-DialogCloseButtonAppearance -Button $close -ForegroundColor $dialogText
    $title.Text = T 'ConfirmTitle'; $messageText.Text = $Message; $cancel.Content = T 'Cancel'; $accept.Content = T 'Confirm'
    $titleBar.Add_MouseLeftButtonDown({ try { $dialog.DragMove() } catch { } })
    $close.Add_Click({ $dialog.Tag=$false; $dialog.DialogResult=$false; $dialog.Close() })
    $cancel.Add_Click({ $dialog.Tag=$false; $dialog.DialogResult=$false; $dialog.Close() })
    $accept.Add_Click({ $dialog.Tag=$true; $dialog.DialogResult=$true; $dialog.Close() })
    return $dialog.ShowDialog() -eq $true -and [bool]$dialog.Tag
}

function Show-AppRestartRecommendedDialog {
    $dialogBackground = Get-AppThemeColor 'WindowBrush' '#20242B'
    $dialogSurface = Get-AppThemeColor 'CardBrush' '#171A1F'
    $dialogText = Get-AppThemeColor 'TextBrush' '#F4F4F4'
    $dialogMuted = Get-AppThemeColor 'MutedBrush' '#A8ADB5'
    $dialogBorder = Get-AppThemeColor 'WindowBorderBrush' '#59616B'
    $dialogAccent = ConvertTo-AccentHex ([string]$script:Settings.AccentColor)
    if (-not $dialogAccent) { $dialogAccent = '#1A9FFF' }
    [xml]$restartXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="500" Height="225" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" Foreground="$dialogText">
  <Window.Resources><Style x:Key="RestartButtonStyle" TargetType="Button"><Setter Property="Height" Value="32"/><Setter Property="MinWidth" Value="112"/><Setter Property="Padding" Value="12,4"/><Setter Property="Foreground" Value="$dialogText"/><Setter Property="Background" Value="$dialogSurface"/><Setter Property="BorderBrush" Value="$dialogBorder"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="$dialogAccent"/><Setter TargetName="B" Property="BorderBrush" Value="$dialogAccent"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger><MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="Close"/></MultiTrigger.Conditions><Setter TargetName="B" Property="Background" Value="#D13438"/><Setter TargetName="B" Property="BorderBrush" Value="#D13438"/><Setter Property="Foreground" Value="#FFFFFF"/></MultiTrigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style></Window.Resources>
  <Border Margin="1" Background="$dialogBackground" BorderBrush="$dialogBorder" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))"><Grid><Grid.RowDefinitions><RowDefinition Height="42"/><RowDefinition Height="*"/></Grid.RowDefinitions><Border x:Name="RestartTitleBar" Background="$dialogSurface" CornerRadius="$([int](Get-AppCornerRadiusValue)),$([int](Get-AppCornerRadiusValue)),0,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="34"/><ColumnDefinition Width="8"/></Grid.ColumnDefinitions><TextBlock x:Name="RestartTitle" Margin="12,0" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold"/><Button x:Name="RestartClose" Grid.Column="1" Style="{StaticResource RestartButtonStyle}" Tag="Close" Content="×" Padding="0" MinWidth="0" Width="28" Height="28"/></Grid></Border><Grid Grid.Row="1" Margin="16,14"><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock x:Name="RestartMessage" Foreground="$dialogMuted" TextWrapping="Wrap" VerticalAlignment="Center" FontSize="12"/><StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0"><Button x:Name="RestartLater" Style="{StaticResource RestartButtonStyle}" IsCancel="True"/><Button x:Name="RestartNow" Style="{StaticResource RestartButtonStyle}" IsDefault="True" Margin="8,0,0,0"/></StackPanel></Grid></Grid></Border>
</Window>
"@
    $reader = New-Object Xml.XmlNodeReader($restartXaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    $dialog.Owner = $window
    $dialog.FontFamily = $script:UiFontFamily
    Enable-RoundedDialogFrame $dialog
    $titleBar=$dialog.FindName('RestartTitleBar'); $title=$dialog.FindName('RestartTitle'); $message=$dialog.FindName('RestartMessage'); $close=$dialog.FindName('RestartClose'); $later=$dialog.FindName('RestartLater'); $restart=$dialog.FindName('RestartNow')
    Set-DialogCloseButtonAppearance -Button $close -ForegroundColor $dialogText
    $title.Text=T 'RestartRecommendedTitle'; $message.Text=T 'RestartRecommendedMessage'; $later.Content=T 'RestartLater'; $restart.Content=T 'RestartNow'
    $titleBar.Add_MouseLeftButtonDown({ try { $dialog.DragMove() } catch { } })
    $close.Add_Click({ $dialog.Tag=$false; $dialog.DialogResult=$false; $dialog.Close() })
    $later.Add_Click({ $dialog.Tag=$false; $dialog.DialogResult=$false; $dialog.Close() })
    $restart.Add_Click({ $dialog.Tag=$true; $dialog.DialogResult=$true; $dialog.Close() })
    return $dialog.ShowDialog() -eq $true -and [bool]$dialog.Tag
}

function Show-AppTextPrompt {
    param([Parameter(Mandatory=$true)][string]$Title,[Parameter(Mandatory=$true)][string]$Hint,[string]$InitialValue='',[int]$MaxLength=255)
    $dialogBackground = Get-AppThemeColor 'WindowBrush' '#20242B'
    $dialogSurface = Get-AppThemeColor 'CardBrush' '#171A1F'
    $dialogInput = Get-AppThemeColor 'InputBrush' '#111419'
    $dialogText = Get-AppThemeColor 'TextBrush' '#F4F4F4'
    $dialogMuted = Get-AppThemeColor 'MutedBrush' '#A8ADB5'
    $dialogBorder = Get-AppThemeColor 'WindowBorderBrush' '#59616B'
    $dialogAccent = ConvertTo-AccentHex ([string]$script:Settings.AccentColor); if (-not $dialogAccent) { $dialogAccent='#1A9FFF' }
    [xml]$promptXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Width="470" Height="225" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" Foreground="$dialogText">
  <Window.Resources><Style x:Key="PromptButtonStyle" TargetType="Button"><Setter Property="Height" Value="32"/><Setter Property="MinWidth" Value="92"/><Setter Property="Padding" Value="12,4"/><Setter Property="Foreground" Value="$dialogText"/><Setter Property="Background" Value="$dialogSurface"/><Setter Property="BorderBrush" Value="$dialogBorder"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="$dialogAccent"/><Setter TargetName="B" Property="BorderBrush" Value="$dialogAccent"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger><MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="Close"/></MultiTrigger.Conditions><Setter TargetName="B" Property="Background" Value="#D13438"/><Setter TargetName="B" Property="BorderBrush" Value="#D13438"/><Setter Property="Foreground" Value="#FFFFFF"/></MultiTrigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style></Window.Resources>
  <Border Margin="1" Background="$dialogBackground" BorderBrush="$dialogBorder" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))"><Grid><Grid.RowDefinitions><RowDefinition Height="42"/><RowDefinition Height="*"/></Grid.RowDefinitions><Border x:Name="PromptTitleBar" Background="$dialogSurface" CornerRadius="$([int](Get-AppCornerRadiusValue)),$([int](Get-AppCornerRadiusValue)),0,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="34"/><ColumnDefinition Width="8"/></Grid.ColumnDefinitions><TextBlock x:Name="PromptTitle" Margin="12,0" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold"/><Button x:Name="PromptClose" Grid.Column="1" Style="{StaticResource PromptButtonStyle}" Tag="Close" Content="×" Padding="0" MinWidth="0" Width="28" Height="28"/></Grid></Border><Grid Grid.Row="1" Margin="16,14"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><TextBlock x:Name="PromptHint" Foreground="$dialogMuted" TextWrapping="Wrap"/><Border Grid.Row="1" Margin="0,10,0,0" Background="$dialogInput" BorderBrush="$dialogBorder" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))"><TextBox x:Name="PromptValue" Height="34" Margin="1" Padding="9,4" MaxLength="$MaxLength" Foreground="$dialogText" Background="Transparent" BorderThickness="0" CaretBrush="$dialogText" VerticalContentAlignment="Center"/></Border><StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,13,0,0"><Button x:Name="PromptCancel" Style="{StaticResource PromptButtonStyle}" IsCancel="True"/><Button x:Name="PromptAccept" Style="{StaticResource PromptButtonStyle}" IsDefault="True" Margin="8,0,0,0"/></StackPanel></Grid></Grid></Border>
</Window>
"@
    $reader=New-Object Xml.XmlNodeReader($promptXaml); $dialog=[Windows.Markup.XamlReader]::Load($reader); $dialog.Owner=$window; $dialog.FontFamily=$script:UiFontFamily; Enable-RoundedDialogFrame $dialog
    $titleBar=$dialog.FindName('PromptTitleBar'); $titleText=$dialog.FindName('PromptTitle'); $close=$dialog.FindName('PromptClose'); $hintText=$dialog.FindName('PromptHint'); $valueBox=$dialog.FindName('PromptValue'); $cancel=$dialog.FindName('PromptCancel'); $accept=$dialog.FindName('PromptAccept')
    Set-DialogCloseButtonAppearance -Button $close -ForegroundColor $dialogText
    $titleText.Text=$Title; $hintText.Text=$Hint; $valueBox.Text=$InitialValue; $cancel.Content=T 'Cancel'; $accept.Content=T 'Confirm'
    $titleBar.Add_MouseLeftButtonDown({try{$dialog.DragMove()}catch{}}); $close.Add_Click({$dialog.DialogResult=$false;$dialog.Close()}); $cancel.Add_Click({$dialog.DialogResult=$false;$dialog.Close()}); $accept.Add_Click({$dialog.Tag=$valueBox.Text.Trim();$dialog.DialogResult=$true;$dialog.Close()})
    $dialog.Add_ContentRendered({$valueBox.Focus();$valueBox.SelectAll()})
    if($dialog.ShowDialog() -eq $true){return [string]$dialog.Tag}; return $null
}

function Show-BackupDetailsDialog {
    param([Parameter(Mandatory = $true)][object]$Row)

    $root = [IO.Path]::GetFullPath($script:Paths.BackupRoot).TrimEnd('\') + '\'
    $path = [IO.Path]::GetFullPath([string]$Row.Path)
    if (-not $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw (T 'PreviewUnavailable') }
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
    $bytes = [IO.File]::ReadAllBytes($path)
    $lines = @([IO.File]::ReadAllLines($path))
    $nonEmptyLines = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    $mappingLines = @($lines | Where-Object { $value=$_.Trim(); $value -and -not $value.StartsWith('#') }).Count
    $encoding = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 'UTF-8 BOM' } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { 'UTF-16 LE' } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { 'UTF-16 BE' } else { 'UTF-8 / ASCII sans BOM' }
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash
    $owner = T 'Unavailable'
    $permissions = T 'Unavailable'
    try {
        $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
        $owner = [string]$acl.Owner
        $permissions = @($acl.Access | ForEach-Object { '{0} — {1} — {2}{3}' -f $_.IdentityReference,$_.FileSystemRights,$_.AccessControlType,$(if ($_.IsInherited) { ' — ' + (T 'Inherited') } else { '' }) }) -join "`r`n"
        if ([string]::IsNullOrWhiteSpace($permissions)) { $permissions = T 'Unavailable' }
    }
    catch { }
    $details = New-Object Text.StringBuilder
    foreach ($pair in @(
        @((T 'DetailName'),$item.Name),
        @((T 'DetailPath'),$item.FullName),
        @((T 'DetailSize'),((Format-Size $item.Length) + ' (' + $item.Length + ' ' + (T 'Bytes') + ')')),
        @((T 'DetailCreated'),$item.CreationTime.ToString('F')),
        @((T 'DetailModified'),$item.LastWriteTime.ToString('F')),
        @((T 'DetailAccessed'),$item.LastAccessTime.ToString('F')),
        @((T 'DetailLines'),$lines.Count),
        @((T 'DetailNonEmptyLines'),$nonEmptyLines),
        @((T 'DetailMappings'),$mappingLines),
        @((T 'DetailEncoding'),$encoding),
        @((T 'DetailAttributes'),[string]$item.Attributes),
        @((T 'DetailReadOnly'),[bool]($item.Attributes -band [IO.FileAttributes]::ReadOnly)),
        @((T 'DetailOwner'),$owner),
        @('SHA-256',$hash)
    )) { [void]$details.AppendLine(('{0} : {1}' -f $pair[0],$pair[1])) }
    [void]$details.AppendLine(); [void]$details.AppendLine((T 'DetailPermissions')); [void]$details.AppendLine($permissions)

    $dialogBackground = Get-AppThemeColor 'WindowBrush' '#20242B'
    $dialogSurface = Get-AppThemeColor 'CardBrush' '#171A1F'
    $dialogInput = Get-AppThemeColor 'InputBrush' '#111318'
    $dialogText = Get-AppThemeColor 'TextBrush' '#F4F4F4'
    $dialogBorder = Get-AppThemeColor 'WindowBorderBrush' '#59616B'
    $dialogAccent = ConvertTo-AccentHex ([string]$script:Settings.AccentColor); if (-not $dialogAccent) { $dialogAccent='#1A9FFF' }
    [xml]$detailsXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework" Width="690" MinWidth="520" Height="520" MinHeight="380" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="CanResize" AllowsTransparency="True" Background="Transparent" Foreground="$dialogText">
  <shell:WindowChrome.WindowChrome><shell:WindowChrome CaptionHeight="0" ResizeBorderThickness="6" CornerRadius="$([int](Get-AppCornerRadiusValue))" GlassFrameThickness="0" UseAeroCaptionButtons="False"/></shell:WindowChrome.WindowChrome>
  <Window.Resources><Style x:Key="DetailsButton" TargetType="Button"><Setter Property="Height" Value="32"/><Setter Property="Padding" Value="12,4"/><Setter Property="Foreground" Value="$dialogText"/><Setter Property="Background" Value="$dialogSurface"/><Setter Property="BorderBrush" Value="$dialogBorder"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="$dialogAccent"/><Setter TargetName="B" Property="BorderBrush" Value="$dialogAccent"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger><MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="Close"/></MultiTrigger.Conditions><Setter TargetName="B" Property="Background" Value="#D13438"/><Setter TargetName="B" Property="BorderBrush" Value="#D13438"/><Setter Property="Foreground" Value="#FFFFFF"/></MultiTrigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style></Window.Resources>
  <Border Margin="1" Background="$dialogBackground" BorderBrush="$dialogBorder" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))"><Grid><Grid.RowDefinitions><RowDefinition Height="42"/><RowDefinition Height="*"/></Grid.RowDefinitions><Border x:Name="DetailsTitleBar" Background="$dialogSurface" CornerRadius="$([int](Get-AppCornerRadiusValue)),$([int](Get-AppCornerRadiusValue)),0,0"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="34"/><ColumnDefinition Width="8"/></Grid.ColumnDefinitions><TextBlock x:Name="DetailsTitle" Margin="12,0" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold"/><Button x:Name="DetailsClose" Grid.Column="1" Style="{StaticResource DetailsButton}" Tag="Close" Content="×" Padding="0" Width="28" Height="28"/></Grid></Border><Grid Grid.Row="1" Margin="14"><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions><Border Background="$dialogInput" BorderBrush="$dialogBorder" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))"><TextBox x:Name="DetailsText" Margin="1" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Background="Transparent" BorderThickness="0" Foreground="$dialogText" Padding="10" FontFamily="Consolas" FontSize="11"/></Border><StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0"><Button x:Name="DetailsOpen" Style="{StaticResource DetailsButton}"/><Button x:Name="DetailsDone" Style="{StaticResource DetailsButton}" Margin="8,0,0,0"/></StackPanel></Grid></Grid></Border>
</Window>
"@
    $reader=New-Object Xml.XmlNodeReader($detailsXaml); $dialog=[Windows.Markup.XamlReader]::Load($reader); $dialog.Owner=$window; $dialog.FontFamily=$script:UiFontFamily; Enable-RoundedDialogFrame $dialog
    $titleBar=$dialog.FindName('DetailsTitleBar'); $title=$dialog.FindName('DetailsTitle'); $close=$dialog.FindName('DetailsClose'); $textBox=$dialog.FindName('DetailsText'); $open=$dialog.FindName('DetailsOpen'); $done=$dialog.FindName('DetailsDone')
    Set-DialogCloseButtonAppearance -Button $close -ForegroundColor $dialogText
    $title.Text=T 'BackupDetailsTitle'; $textBox.Text=$details.ToString(); $open.Content=T 'OpenFile'; $done.Content=T 'Close'
    $titleBar.Add_MouseLeftButtonDown({try{$dialog.DragMove()}catch{}}); $close.Add_Click({$dialog.Close()}); $done.Add_Click({$dialog.Close()}); $open.Add_Click({try{Open-TextFile -Path $path}catch{Show-AppError $_.Exception.Message}})
    [void]$dialog.ShowDialog()
}

function Show-AppxDetailsDialog {
    param([Parameter(Mandatory = $true)][object]$Row)

    $displayName = if ([string]::IsNullOrWhiteSpace([string]$Row.DisplayName)) { [string]$Row.PackageName } else { [string]$Row.DisplayName }
    $details = New-Object Text.StringBuilder

    function Add-AppxDetailLine {
        param([string]$Label,[object]$Value)
        $text = ''
        if ($null -ne $Value) {
            if ($Value -is [System.Array]) { $text = @($Value | ForEach-Object { [string]$_ } | Where-Object { $_ }) -join "`r`n    " }
            else { $text = [string]$Value }
        }
        if ([string]::IsNullOrWhiteSpace($text)) { $text = T 'Unavailable' }
        [void]$details.AppendLine(('{0} : {1}' -f $Label,$text))
    }

    Add-AppxDetailLine -Label (T 'DetailName') -Value $displayName
    Add-AppxDetailLine -Label 'PackageName' -Value ([string]$Row.PackageName)
    Add-AppxDetailLine -Label 'PackageFamilyName' -Value ([string]$Row.PackageFamilyName)
    Add-AppxDetailLine -Label 'PackageFullName' -Value @($Row.InstalledPackageFullNames)
    Add-AppxDetailLine -Label 'Version' -Value @($Row.Versions)
    Add-AppxDetailLine -Label 'Architecture' -Value @($Row.Architectures)
    Add-AppxDetailLine -Label 'Publisher' -Value @($Row.Publishers)
    Add-AppxDetailLine -Label 'SignatureKind' -Value @($Row.SignatureKinds)
    Add-AppxDetailLine -Label 'InstallLocation' -Value @($Row.InstallLocations)
    Add-AppxDetailLine -Label 'ProvisionedPackageName' -Value @($Row.ProvisionedPackageNames)
    Add-AppxDetailLine -Label 'Installed' -Value ([bool]$Row.Installed)
    Add-AppxDetailLine -Label 'Provisioned' -Value ([bool]$Row.Provisioned)
    Add-AppxDetailLine -Label 'Classification' -Value ([string]$Row.Indicator)
    Add-AppxDetailLine -Label 'ReasonCode' -Value ([string]$Row.ReasonCode)
    Add-AppxDetailLine -Label 'Hidden' -Value ([bool]$Row.IsHidden)
    [void]$details.AppendLine()
    [void]$details.AppendLine((T 'AppxDescriptionHeader') + ' :')
    [void]$details.AppendLine([string]$Row.Description)

    $location = @($Row.InstallLocations | Where-Object { $_ -and (Test-Path -LiteralPath ([string]$_) -PathType Container) } | Select-Object -First 1)
    $location = if ($location.Count -gt 0) { [string]$location[0] } else { '' }

    $dialogBackground = Get-AppThemeColor 'WindowBrush' '#20242B'
    $dialogSurface = Get-AppThemeColor 'CardBrush' '#171A1F'
    $dialogInput = Get-AppThemeColor 'InputBrush' '#111318'
    $dialogText = Get-AppThemeColor 'TextBrush' '#F4F4F4'
    $dialogBorder = Get-AppThemeColor 'WindowBorderBrush' '#59616B'
    $dialogAccent = ConvertTo-AccentHex ([string]$script:Settings.AccentColor)
    if (-not $dialogAccent) { $dialogAccent = '#1A9FFF' }

    [xml]$detailsXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework" Width="760" MinWidth="560" Height="600" MinHeight="420" WindowStartupLocation="CenterOwner" WindowStyle="None" ResizeMode="CanResize" AllowsTransparency="True" Background="Transparent" Foreground="$dialogText">
  <shell:WindowChrome.WindowChrome><shell:WindowChrome CaptionHeight="0" ResizeBorderThickness="6" CornerRadius="$([int](Get-AppCornerRadiusValue))" GlassFrameThickness="0" UseAeroCaptionButtons="False"/></shell:WindowChrome.WindowChrome>
  <Window.Resources>
    <Style x:Key="DetailsButton" TargetType="Button">
      <Setter Property="Height" Value="32"/><Setter Property="Padding" Value="12,4"/><Setter Property="Foreground" Value="$dialogText"/><Setter Property="Background" Value="$dialogSurface"/><Setter Property="BorderBrush" Value="$dialogBorder"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="B" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="B" Property="Background" Value="$dialogAccent"/><Setter TargetName="B" Property="BorderBrush" Value="$dialogAccent"/><Setter Property="Foreground" Value="#FFFFFF"/></Trigger><MultiTrigger><MultiTrigger.Conditions><Condition Property="IsMouseOver" Value="True"/><Condition Property="Tag" Value="Close"/></MultiTrigger.Conditions><Setter TargetName="B" Property="Background" Value="#D13438"/><Setter TargetName="B" Property="BorderBrush" Value="#D13438"/><Setter Property="Foreground" Value="#FFFFFF"/></MultiTrigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Border Margin="1" Background="$dialogBackground" BorderBrush="$dialogBorder" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))">
    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="42"/><RowDefinition Height="*"/></Grid.RowDefinitions>
      <Border x:Name="DetailsTitleBar" Background="$dialogSurface" CornerRadius="$([int](Get-AppCornerRadiusValue)),$([int](Get-AppCornerRadiusValue)),0,0">
        <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="34"/><ColumnDefinition Width="8"/></Grid.ColumnDefinitions><TextBlock x:Name="DetailsTitle" Margin="12,0" VerticalAlignment="Center" FontSize="15" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/><Button x:Name="DetailsClose" Grid.Column="1" Style="{StaticResource DetailsButton}" Tag="Close" Content="×" Padding="0" Width="28" Height="28"/></Grid>
      </Border>
      <Grid Grid.Row="1" Margin="14">
        <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <Border Background="$dialogInput" BorderBrush="$dialogBorder" BorderThickness="1" CornerRadius="$([int](Get-AppCornerRadiusValue))">
          <TextBox x:Name="DetailsText" Margin="1" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Background="Transparent" BorderThickness="0" Foreground="$dialogText" Padding="10" FontFamily="Consolas" FontSize="11"/>
        </Border>
        <StackPanel Grid.Row="1" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
          <Button x:Name="DetailsOpen" Style="{StaticResource DetailsButton}"/>
          <Button x:Name="DetailsDone" Style="{StaticResource DetailsButton}" Margin="8,0,0,0"/>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>
"@

    $reader = New-Object Xml.XmlNodeReader($detailsXaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    $dialog.Owner = $window
    $dialog.FontFamily = $script:UiFontFamily
    Enable-RoundedDialogFrame $dialog

    $titleBar = $dialog.FindName('DetailsTitleBar')
    $title = $dialog.FindName('DetailsTitle')
    $close = $dialog.FindName('DetailsClose')
    $textBox = $dialog.FindName('DetailsText')
    $open = $dialog.FindName('DetailsOpen')
    $done = $dialog.FindName('DetailsDone')

    Set-DialogCloseButtonAppearance -Button $close -ForegroundColor $dialogText
    $title.Text = (T 'AppxDetailsTitle') + ' — ' + $displayName
    $textBox.Text = $details.ToString()
    $open.Content = T 'OpenLocation'
    $open.IsEnabled = -not [string]::IsNullOrWhiteSpace($location)
    $done.Content = T 'Close'

    $titleBar.Add_MouseLeftButtonDown({ try { $dialog.DragMove() } catch {} })
    $close.Add_Click({ $dialog.Close() })
    $done.Add_Click({ $dialog.Close() })
    $open.Add_Click({
        if ([string]::IsNullOrWhiteSpace($location)) { return }
        try { Start-Process -FilePath 'explorer.exe' -ArgumentList @($location) }
        catch { Show-AppError $_.Exception.Message }
    })

    [void]$dialog.ShowDialog()
}
