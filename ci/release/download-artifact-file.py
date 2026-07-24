#!/usr/bin/env python3
"""Download one file from a GitHub Actions artifact using HTTP ranges."""

from __future__ import annotations

import argparse
import concurrent.futures
import io
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class HTTPRangeReader(io.RawIOBase):
    def __init__(self, url: str):
        self.url = url
        self.position = 0
        request = urllib.request.Request(url, headers={"Range": "bytes=0-0"})
        with urllib.request.urlopen(request) as response:
            content_range = response.headers.get("Content-Range", "")
            match = re.fullmatch(r"bytes 0-0/(\d+)", content_range)
            if response.status != 206 or not match:
                raise RuntimeError("Artifact storage does not support HTTP ranges")
            self.length = int(match.group(1))

    def readable(self) -> bool:
        return True

    def seekable(self) -> bool:
        return True

    def tell(self) -> int:
        return self.position

    def seek(self, offset: int, whence: int = io.SEEK_SET) -> int:
        if whence == io.SEEK_SET:
            position = offset
        elif whence == io.SEEK_CUR:
            position = self.position + offset
        elif whence == io.SEEK_END:
            position = self.length + offset
        else:
            raise ValueError(f"Unsupported seek mode: {whence}")
        if position < 0:
            raise ValueError("Negative seek position")
        self.position = min(position, self.length)
        return self.position

    def read(self, size: int = -1) -> bytes:
        if self.position >= self.length:
            return b""
        if size is None or size < 0:
            end = self.length - 1
        else:
            end = min(self.position + size, self.length) - 1
        if end < self.position:
            return b""

        expected = end - self.position + 1
        if expected >= 1024 * 1024:
            print(
                f"Fetching ZIP range {self.position}-{end} "
                f"({expected} bytes)",
                file=sys.stderr,
                flush=True,
            )
        if expected >= 1024 * 1024:
            chunk_size = 2 * 1024 * 1024
            ranges = [
                (start, min(start + chunk_size - 1, end))
                for start in range(self.position, end + 1, chunk_size)
            ]
            with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
                data = b"".join(executor.map(lambda bounds: self._fetch(*bounds), ranges))
        else:
            data = self._fetch(self.position, end)
        self.position += len(data)
        return data

    def _fetch(self, start: int, end: int) -> bytes:
        expected = end - start + 1
        for attempt in range(1, 6):
            request = urllib.request.Request(
                self.url, headers={"Range": f"bytes={start}-{end}"}
            )
            try:
                with urllib.request.urlopen(request, timeout=180) as response:
                    data = response.read()
                    if response.status != 206 or len(data) != expected:
                        raise RuntimeError(
                            f"Unexpected range response: status={response.status}, "
                            f"bytes={len(data)}, expected={expected}"
                        )
                    return data
            except (OSError, RuntimeError, urllib.error.URLError):
                if attempt == 5:
                    raise
                time.sleep(attempt * 2)
        raise AssertionError("unreachable")


def artifact_download_url(api_url: str, token: str) -> str:
    opener = urllib.request.build_opener(NoRedirect)
    request = urllib.request.Request(
        api_url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "acefox-release-workflow",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        opener.open(request)
    except urllib.error.HTTPError as error:
        if error.code != 302:
            raise
        location = error.headers.get("Location")
        if not location:
            raise RuntimeError("GitHub artifact response omitted redirect URL") from error
        parsed = urllib.parse.urlparse(location)
        if parsed.scheme != "https" or not parsed.hostname:
            raise RuntimeError("GitHub returned an unsafe artifact redirect URL")
        return location
    raise RuntimeError("GitHub artifact endpoint did not redirect to storage")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact_api_url")
    parser.add_argument("member_suffix")
    parser.add_argument("output_directory", type=Path)
    parser.add_argument("--list-only", action="store_true")
    args = parser.parse_args()

    token = os.environ.get("GH_TOKEN")
    if not token:
        parser.error("GH_TOKEN is required")

    storage_url = artifact_download_url(args.artifact_api_url, token)
    reader = HTTPRangeReader(storage_url)
    with zipfile.ZipFile(reader) as archive:
        matches = [
            member
            for member in archive.infolist()
            if not member.is_dir() and member.filename.endswith(args.member_suffix)
        ]
        if len(matches) != 1:
            names = ", ".join(member.filename for member in matches) or "none"
            raise RuntimeError(
                f"Expected one *{args.member_suffix} artifact member, found: {names}"
            )
        member = matches[0]
        print(
            f"Selected {member.filename} "
            f"({member.file_size} bytes, {member.compress_size} compressed)"
        )
        if args.list_only:
            return 0

        args.output_directory.mkdir(parents=True, exist_ok=True)
        output = args.output_directory / Path(member.filename).name
        temporary = output.with_suffix(output.suffix + ".partial")
        with archive.open(member) as source, temporary.open("wb") as destination:
            shutil.copyfileobj(source, destination, length=128 * 1024 * 1024)
        temporary.replace(output)
        print(f"Extracted {output} ({output.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
