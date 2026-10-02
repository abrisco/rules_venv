"""A test for provider tests."""

import unittest

from python.venv.private.tests.providers.lib import GREETING


class GreetingTest(unittest.TestCase):
    """Test the greeting."""

    def test_greeting(self) -> None:
        """Ensure the greeting is correct."""
        self.assertEqual(GREETING, "La-Li-Lu-Le-Lo")


if __name__ == "__main__":
    unittest.main()
