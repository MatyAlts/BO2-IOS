"""Regression contract for the actual unsigned device IPA, not project settings."""
import os
import struct
import unittest
import zipfile


class StandardIPAContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with zipfile.ZipFile(os.environ["IPA_PATH"]) as archive:
            cls.binary = archive.read("Payload/RuntimeProbe.app/RuntimeProbe")
        if struct.unpack_from("<I", cls.binary)[0] != 0xFEEDFACF:
            raise AssertionError("Expected thin little-endian Mach-O64 device executable")
        cls.segments = {}
        cls.dependencies = []
        offset = 32
        for _ in range(struct.unpack_from("<I", cls.binary, 16)[0]):
            command, size = struct.unpack_from("<II", cls.binary, offset)
            if size < 8 or offset + size > len(cls.binary):
                raise AssertionError("Invalid Mach-O load command bounds")
            if command == 0x19:
                name = cls.binary[offset + 8:offset + 24].split(b"\0")[0].decode()
                address, memory_size, file_offset, file_size = struct.unpack_from("<QQQQ", cls.binary, offset + 24)
                cls.segments[name] = (address, memory_size, file_offset, file_size)
            if command in (0xC, 0x80000018, 0x8000001F):
                name_offset = struct.unpack_from("<I", cls.binary, offset + 8)[0]
                cls.dependencies.append(cls.binary[offset + name_offset:offset + size].split(b"\0")[0].decode())
            offset += size

    def test_arm64_device_has_hard_pagezero_covering_four_gib(self):
        # Public XNU mach_loader.c requires a hard 4GiB pagezero for arm64.
        address, size, file_offset, file_size = self.segments["__PAGEZERO"]
        self.assertEqual(address, 0)
        self.assertGreaterEqual(size, 0x100000000,
            "Device __PAGEZERO is below the arm64 loader minimum; reduced layout can fail before main")
        self.assertEqual((file_offset, file_size), (0, 0))

    def test_signed_text_is_outside_protected_low_window(self):
        address, size, _, file_size = self.segments["__TEXT"]
        self.assertGreaterEqual(address, 0x100000000)
        self.assertGreater(size, 0)
        self.assertGreater(file_size, 0)
        self.assertTrue(self.dependencies, "Device executable must have its system dependencies inventoried")


if __name__ == "__main__":
    unittest.main()
