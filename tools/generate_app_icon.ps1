# Regenerate the Windows and web icons from one vector drawing.
# Run from any directory: powershell -File tools/generate_app_icon.ps1
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

public static class SancIcon {
  static GraphicsPath Rounded(float x, float y, float w, float h, float r) {
    var p = new GraphicsPath();
    p.AddArc(x, y, r * 2, r * 2, 180, 90);
    p.AddArc(x + w - r * 2, y, r * 2, r * 2, 270, 90);
    p.AddArc(x + w - r * 2, y + h - r * 2, r * 2, r * 2, 0, 90);
    p.AddArc(x, y + h - r * 2, r * 2, r * 2, 90, 90);
    p.CloseFigure();
    return p;
  }

  static Bitmap Master(bool maskable) {
    var bmp = new Bitmap(1024, 1024, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(bmp)) {
      g.SmoothingMode = SmoothingMode.AntiAlias;
      g.CompositingQuality = CompositingQuality.HighQuality;
      g.PixelOffsetMode = PixelOffsetMode.HighQuality;
      g.Clear(maskable ? Color.FromArgb(13, 86, 88) : Color.Transparent);
      g.ScaleTransform(4, 4);

      using (var tile = Rounded(14, 14, 228, 228, 52))
      using (var gradient = new LinearGradientBrush(
          new PointF(26, 25), new PointF(222, 235),
          Color.FromArgb(31, 154, 145), Color.FromArgb(9, 78, 88))) {
        g.FillPath(gradient, tile);
        using (var rim = new Pen(Color.FromArgb(72, 255, 255, 255), 2))
          g.DrawPath(rim, tile);
      }

      // Keep the recognizable peaked frame from the original app icon.
      using (var frame = new GraphicsPath()) {
        frame.StartFigure();
        frame.AddLine(56, 90, 92, 90);
        frame.AddLine(92, 90, 128, 54);
        frame.AddLine(128, 54, 164, 90);
        frame.AddLine(164, 90, 200, 90);
        frame.AddArc(200, 90, 12, 12, 270, 90);
        frame.AddLine(212, 102, 212, 190);
        frame.AddArc(200, 190, 12, 12, 0, 90);
        frame.AddLine(200, 202, 56, 202);
        frame.AddArc(44, 190, 12, 12, 90, 90);
        frame.AddLine(44, 190, 44, 102);
        frame.AddArc(44, 90, 12, 12, 180, 90);
        frame.CloseFigure();
        using (var outline = new Pen(Color.FromArgb(245, 254, 251), 13)) {
          outline.LineJoin = LineJoin.Round;
          outline.StartCap = LineCap.Round;
          outline.EndCap = LineCap.Round;
          g.DrawPath(outline, frame);
        }
      }

      using (var photo = Rounded(72, 108, 112, 76, 10)) {
        using (var sky = new SolidBrush(Color.FromArgb(224, 248, 242)))
          g.FillPath(sky, photo);
        var previousClip = g.Clip;
        g.SetClip(photo);
        using (var sun = new SolidBrush(Color.FromArgb(255, 188, 91)))
          g.FillEllipse(sun, 148, 120, 19, 19);
        using (var distant = new SolidBrush(Color.FromArgb(101, 190, 179)))
          g.FillPolygon(distant, new[] {
            new Point(70, 179), new Point(117, 135),
            new Point(158, 178), new Point(186, 152), new Point(190, 188)
          });
        using (var foreground = new SolidBrush(Color.FromArgb(22, 115, 110)))
          g.FillPolygon(foreground, new[] {
            new Point(68, 185), new Point(93, 157),
            new Point(124, 181), new Point(153, 154),
            new Point(190, 186)
          });
        g.Clip = previousClip;
        using (var border = new Pen(Color.FromArgb(243, 255, 252), 4))
          g.DrawPath(border, photo);
      }
    }
    return bmp;
  }

  static byte[] Png(Bitmap image) {
    using (var stream = new MemoryStream()) {
      image.Save(stream, ImageFormat.Png);
      return stream.ToArray();
    }
  }

  static byte[] Render(Bitmap master, int size) {
    using (var target = new Bitmap(size, size, PixelFormat.Format32bppArgb)) {
      using (var g = Graphics.FromImage(target)) {
        g.Clear(Color.Transparent);
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        g.CompositingQuality = CompositingQuality.HighQuality;
        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        g.DrawImage(master, new Rectangle(0, 0, size, size));
      }
      return Png(target);
    }
  }

  static void Save(string root, string relative, byte[] data) {
    var path = Path.Combine(root, relative);
    Directory.CreateDirectory(Path.GetDirectoryName(path));
    File.WriteAllBytes(path, data);
  }

  public static void Generate(string root) {
    using (var master = Master(false)) {
      Save(root, @"windows\runner\resources\app_icon.png", Render(master, 256));
      Save(root, @"web\favicon.png", Render(master, 32));
      Save(root, @"web\icons\Icon-192.png", Render(master, 192));
      Save(root, @"web\icons\Icon-512.png", Render(master, 512));

      int[] sizes = { 16, 24, 32, 48, 64, 128, 256 };
      var images = new List<byte[]>();
      foreach (var size in sizes) images.Add(Render(master, size));
      using (var stream = new MemoryStream())
      using (var writer = new BinaryWriter(stream)) {
        writer.Write((ushort)0);
        writer.Write((ushort)1);
        writer.Write((ushort)sizes.Length);
        int offset = 6 + sizes.Length * 16;
        for (int i = 0; i < sizes.Length; i++) {
          writer.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
          writer.Write((byte)(sizes[i] == 256 ? 0 : sizes[i]));
          writer.Write((byte)0);
          writer.Write((byte)0);
          writer.Write((ushort)1);
          writer.Write((ushort)32);
          writer.Write((uint)images[i].Length);
          writer.Write((uint)offset);
          offset += images[i].Length;
        }
        foreach (var image in images) writer.Write(image);
        Save(root, @"windows\runner\resources\app_icon.ico", stream.ToArray());
      }
    }

    using (var maskable = Master(true)) {
      Save(root, @"web\icons\Icon-maskable-192.png", Render(maskable, 192));
      Save(root, @"web\icons\Icon-maskable-512.png", Render(maskable, 512));
    }
  }
}
'@

[SancIcon]::Generate($projectRoot)
