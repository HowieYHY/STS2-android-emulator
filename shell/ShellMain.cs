using Godot;

namespace StsAndroidShell;

/// <summary>
/// Shown only when the APK runs without the overlay pack (game files not pushed yet).
/// </summary>
public partial class ShellMain : Control
{
    public override void _Ready()
    {
        var label = new Label
        {
            Text = "Game files not found.\nRun scripts/push-game.ps1 -GameDir \"<Steam path>\" on your PC.",
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        label.SetAnchorsPreset(LayoutPreset.FullRect);
        AddChild(label);
    }
}
