param(
    [Parameter(Mandatory = $true)]
    [string]$OriginalPath,

    [Parameter(Mandatory = $true)]
    [string]$EditedPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Add-Type -AssemblyName System.Drawing

$original = [System.Drawing.Bitmap]::new($OriginalPath)
$editedInput = [System.Drawing.Bitmap]::new($EditedPath)
$edited = $null

try {
    if ($original.Width -eq $editedInput.Width -and $original.Height -eq $editedInput.Height) {
        $edited = [System.Drawing.Bitmap]::new($editedInput)
    }
    else {
        # Image generation may shift the dimensions by a few pixels. Align only
        # the generated layer; the original base remains pixel-for-pixel intact.
        $edited = [System.Drawing.Bitmap]::new(
            $original.Width,
            $original.Height,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        $alignGraphics = [System.Drawing.Graphics]::FromImage($edited)
        try {
            $alignGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $alignGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $alignGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $alignGraphics.DrawImage(
                $editedInput,
                [System.Drawing.Rectangle]::new(0, 0, $original.Width, $original.Height)
            )
        }
        finally {
            $alignGraphics.Dispose()
        }
    }

    $output = [System.Drawing.Bitmap]::new(
        $original.Width,
        $original.Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $graphics = [System.Drawing.Graphics]::FromImage($output)
        try {
            $graphics.DrawImageUnscaled($original, 0, 0)
        }
        finally {
            $graphics.Dispose()
        }

        # The edited cat is fully inside this rectangle. The perimeter contains
        # only green backdrop/shelf pixels, so feathering cannot soften the cat.
        $left = 630
        $top = 270
        $right = 1174
        $bottom = 570
        $feather = 16.0

        $catBoundary = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $catBoundary.AddPolygon([System.Drawing.Point[]]@(
            [System.Drawing.Point]::new(690, 355),
            [System.Drawing.Point]::new(705, 350),
            [System.Drawing.Point]::new(730, 365),
            [System.Drawing.Point]::new(760, 372),
            [System.Drawing.Point]::new(792, 350),
            [System.Drawing.Point]::new(815, 373),
            [System.Drawing.Point]::new(855, 365),
            [System.Drawing.Point]::new(910, 357),
            [System.Drawing.Point]::new(965, 350),
            [System.Drawing.Point]::new(1005, 355),
            [System.Drawing.Point]::new(1035, 375),
            [System.Drawing.Point]::new(1052, 405),
            [System.Drawing.Point]::new(1058, 437),
            [System.Drawing.Point]::new(1095, 448),
            [System.Drawing.Point]::new(1120, 465),
            [System.Drawing.Point]::new(1128, 488),
            [System.Drawing.Point]::new(1122, 512),
            [System.Drawing.Point]::new(1000, 522),
            [System.Drawing.Point]::new(900, 522),
            [System.Drawing.Point]::new(800, 525),
            [System.Drawing.Point]::new(720, 522),
            [System.Drawing.Point]::new(680, 505),
            [System.Drawing.Point]::new(680, 470),
            [System.Drawing.Point]::new(685, 420)
        ))

        function Test-IsGreenBackdrop([System.Drawing.Color]$color) {
            return (
                $color.G -gt 150 -and
                ($color.G - $color.R) -gt 80 -and
                ($color.G - $color.B) -gt 80
            )
        }

        for ($y = $top; $y -lt $bottom; $y++) {
            for ($x = $left; $x -lt $right; $x++) {
                $edgeDistance = [Math]::Min(
                    [Math]::Min($x - $left, ($right - 1) - $x),
                    [Math]::Min($y - $top, ($bottom - 1) - $y)
                )

                $alpha = [Math]::Min(1.0, [Math]::Max(0.0, $edgeDistance / $feather))
                # Smoothstep gives a seam-free transition without changing the
                # fully opaque cat region.
                $alpha = $alpha * $alpha * (3.0 - 2.0 * $alpha)

                if ($alpha -le 0.0) {
                    continue
                }

                $source = $edited.GetPixel($x, $y)

                # Above and below the shelf, retain generated pixels only for
                # the cat. Green pixels are restored from the original. Where
                # the original still contains the larger cat, reconstruct the
                # green backdrop from clean pixels on both sides.
                $isBackdropBand = ($y -lt 492 -or $y -ge 536)
                $outsideCurrentCat = -not $catBoundary.IsVisible($x, $y)
                if ($outsideCurrentCat -or ($isBackdropBand -and (Test-IsGreenBackdrop $source))) {
                    if ($y -ge 536) {
                        # The girl's hands and keyboard enter the left sampling
                        # column here; sample two clean green pixels on the right.
                        $leftBackdrop = $original.GetPixel(1170, $y)
                        $rightBackdrop = $original.GetPixel(1200, $y)
                        $t = ($x - 630.0) / (1174.0 - 630.0)
                    }
                    else {
                        $leftBackdrop = $original.GetPixel(615, $y)
                        $rightBackdrop = $original.GetPixel(1174, $y)
                        $t = ($x - 615.0) / (1174.0 - 615.0)
                    }
                    $r = [int][Math]::Round($leftBackdrop.R + (($rightBackdrop.R - $leftBackdrop.R) * $t))
                    $g = [int][Math]::Round($leftBackdrop.G + (($rightBackdrop.G - $leftBackdrop.G) * $t))
                    $b = [int][Math]::Round($leftBackdrop.B + (($rightBackdrop.B - $leftBackdrop.B) * $t))
                    $source = [System.Drawing.Color]::FromArgb(255, $r, $g, $b)
                }

                if ($alpha -ge 1.0) {
                    $output.SetPixel($x, $y, $source)
                    continue
                }

                $base = $original.GetPixel($x, $y)
                $r = [int][Math]::Round($base.R + (($source.R - $base.R) * $alpha))
                $g = [int][Math]::Round($base.G + (($source.G - $base.G) * $alpha))
                $b = [int][Math]::Round($base.B + (($source.B - $base.B) * $alpha))
                $output.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $r, $g, $b))
            }
        }

        $output.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $catBoundary.Dispose()
    }
    finally {
        $output.Dispose()
    }
}
finally {
    $original.Dispose()
    $editedInput.Dispose()
    if ($null -ne $edited) {
        $edited.Dispose()
    }
}
