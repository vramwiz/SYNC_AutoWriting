param([string]$CasesPath, [string]$OutputPath)
# 検査JSONのフォントマスクと前後の経路だけをPNG化する。アプリ画面は開かない。
# Copyright (c) 2026 VRAMの魔術師 / SPDX-License-Identifier: GPL-3.0-only
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$cases = Get-Content -LiteralPath $CasesPath -Raw | ConvertFrom-Json
$selected = @($cases | Where-Object { $_.font -eq 'ＭＳ ゴシック' -and $_.character -cin @('ぬ','の','A','X','0','8','き','シ') })
$bmp = [Drawing.Bitmap]::new(760, 48 + $selected.Count * 220)
$g = [Drawing.Graphics]::FromImage($bmp)
$font = [Drawing.Font]::new('Meiryo', 11)
$colours = @('#d94f46','#187eb7','#319354','#a05abd','#df871a','#188d93','#936147')
try {
    $g.Clear([Drawing.Color]::White)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.DrawString('Legacy estimate                               Reference matching', $font, [Drawing.Brushes]::Black, 24, 10)
    for ($r = 0; $r -lt $selected.Count; $r++) {
        $row = $selected[$r]; $mask = [Convert]::FromBase64String($row.mask)
        $scale = [Math]::Min(150.0 / $row.width, 150.0 / $row.height)
        for ($side = 0; $side -lt 2; $side++) {
            $left = 50 + $side * 380; $top = 85 + $r * 220
            $g.DrawString("$($row.character) U+$('{0:X4}' -f [int][char]$row.character) / $($row.reason)", $font, [Drawing.Brushes]::Black, $left - 25, $top - 32)
            for ($y = 0; $y -lt $row.height; $y++) {
                for ($x = 0; $x -lt $row.width; $x++) {
                    if ($mask[$y * $row.width + $x] -eq 0) { continue }
                    $value = 255 - [int]($mask[$y * $row.width + $x] * 0.25)
                    $brush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb($value,$value,$value))
                    try { $g.FillRectangle($brush, [single]($left+$x*$scale), [single]($top+$y*$scale), [single]($scale+0.1), [single]($scale+0.1)) } finally { $brush.Dispose() }
                }
            }
            $paths = $row.before; if ($side -eq 1) { $paths = $row.after }
            for ($s = 0; $s -lt $paths.Count; $s++) {
                $pen = [Drawing.Pen]::new([Drawing.ColorTranslator]::FromHtml($colours[$s % $colours.Count]), 2)
                $points = @($paths[$s] | ForEach-Object { [Drawing.PointF]::new([single]($left+$_[0]*$scale),[single]($top+$_[1]*$scale)) })
                try {
                    if ($points.Count -ge 2) { $g.DrawLines($pen,[Drawing.PointF[]]$points) }
                    $p = $points[0]; $q = $points[-1]
                    $g.FillEllipse([Drawing.Brushes]::Black,$p.X-3,$p.Y-3,6,6)
                    $g.DrawRectangle($pen,$q.X-3,$q.Y-3,6,6)
                    $g.DrawString([string]($s+1),$font,[Drawing.Brushes]::Black,$p.X+3,$p.Y-15)
                } finally { $pen.Dispose() }
            }
        }
    }
    $bmp.Save($OutputPath,[Drawing.Imaging.ImageFormat]::Png)
} finally { $g.Dispose(); $bmp.Dispose(); $font.Dispose() }
