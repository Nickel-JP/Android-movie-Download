import argparse
import io
import pathlib
import struct
import zipfile


def alignment(data):
    if not data.startswith(b'\x7fELF') or data[4] != 2:
        raise ValueError('64bit ELFファイルではありません。')
    offset = struct.unpack_from('<Q', data, 32)[0]
    size, count = struct.unpack_from('<HH', data, 54)
    values = []
    for index in range(count):
        fields = struct.unpack_from('<IIQQQQQQ', data, offset + index * size)
        if fields[0] == 1:
            values.append(fields[-1])
    return min(values)


def main():
    parser = argparse.ArgumentParser(description='配布APKのネイティブライブラリを16KB対応版へ置換する。')
    parser.add_argument('--source-apk', required=True)
    parser.add_argument('--output-apk', required=True)
    parser.add_argument('--library-directory', required=True)
    args = parser.parse_args()
    source = pathlib.Path(args.source_apk).resolve()
    output = pathlib.Path(args.output_apk).resolve()
    if source == output:
        raise ValueError('入力APKと出力APKを分けてください。')
    replacements = {}
    for name in ['libsharpyuv.so', 'libwebpdecoder.so', 'libwebp.so', 'libwebpdemux.so', 'libwebpmux.so']:
        data = pathlib.Path(args.library_directory, name).read_bytes()
        if alignment(data) < 16384:
            raise ValueError(f'{name} は16KB配置ではありません。')
        replacements['usr/lib/' + name] = data
    target = 'lib/arm64-v8a/libffmpeg.zip.so'
    with zipfile.ZipFile(source) as apk:
        buffer = io.BytesIO()
        with zipfile.ZipFile(io.BytesIO(apk.read(target))) as original:
            if not replacements.keys() <= set(original.namelist()):
                raise ValueError('同梱ライブラリの構成が想定と一致しません。')
            with zipfile.ZipFile(buffer, 'w') as patched:
                for entry in original.infolist():
                    patched.writestr(entry, replacements.get(entry.filename, original.read(entry)))
        with zipfile.ZipFile(output, 'w') as result:
            for entry in apk.infolist():
                # 置換後のAPKは同じキーで署名し直す。古いJAR署名は引き継がない。
                if entry.filename.startswith('META-INF/') and entry.filename.endswith(('.SF', '.RSA', '.DSA', '.EC', 'MANIFEST.MF')):
                    continue
                result.writestr(entry, buffer.getvalue() if entry.filename == target else apk.read(entry))
    print('ネイティブライブラリ5個の置換を完了しました。')


if __name__ == '__main__':
    main()
