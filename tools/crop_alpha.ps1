param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [int]$Padding = 12,

    [int]$AlphaThreshold = 1
)

Add-Type -AssemblyName System.Drawing

$source = [System.Drawing.Bitmap]::new($InputPath)
try {
    $bounds = [System.Drawing.Rectangle]::new(0, 0, $source.Width, $source.Height)
    $data = $source.LockBits(
        $bounds,
        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $stride = [Math]::Abs($data.Stride)
        $bytes = [byte[]]::new($stride * $source.Height)
        [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)

        $minX = $source.Width
        $minY = $source.Height
        $maxX = -1
        $maxY = -1

        for ($y = 0; $y -lt $source.Height; $y++) {
            $row = $y * $stride
            for ($x = 0; $x -lt $source.Width; $x++) {
                $alpha = $bytes[$row + ($x * 4) + 3]
                if ($alpha -ge $AlphaThreshold) {
                    if ($x -lt $minX) { $minX = $x }
                    if ($x -gt $maxX) { $maxX = $x }
                    if ($y -lt $minY) { $minY = $y }
                    if ($y -gt $maxY) { $maxY = $y }
                }
            }
        }
    }
    finally {
        $source.UnlockBits($data)
    }

    if ($maxX -lt 0 -or $maxY -lt 0) {
        throw "No visible pixels found."
    }

    $cropLeft = [Math]::Max(0, $minX - $Padding)
    $cropTop = [Math]::Max(0, $minY - $Padding)
    $cropRight = [Math]::Min($source.Width - 1, $maxX + $Padding)
    $cropBottom = [Math]::Min($source.Height - 1, $maxY + $Padding)
    $cropRect = [System.Drawing.Rectangle]::new(
        $cropLeft,
        $cropTop,
        $cropRight - $cropLeft + 1,
        $cropBottom - $cropTop + 1
    )

    $output = [System.Drawing.Bitmap]::new(
        $cropRect.Width,
        $cropRect.Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )

    try {
        $graphics = [System.Drawing.Graphics]::FromImage($output)
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.DrawImage(
                $source,
                [System.Drawing.Rectangle]::new(0, 0, $output.Width, $output.Height),
                $cropRect,
                [System.Drawing.GraphicsUnit]::Pixel
            )
        }
        finally {
            $graphics.Dispose()
        }

        $output.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Output ("{0} => {1}x{2}" -f $OutputPath, $output.Width, $output.Height)
    }
    finally {
        $output.Dispose()
    }
}
finally {
    $source.Dispose()
}
