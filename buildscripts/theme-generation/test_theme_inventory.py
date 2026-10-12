import unittest

import theme_inventory as inv


class InventoryTests(unittest.TestCase):
	def test_counts_are_consistent(self):
		d = inv.collect()
		self.assertGreater(d["total"], 0)
		self.assertEqual(sum(d["per_directory"].values()), d["total"])
		self.assertEqual(sum(d["shapes"].values()), d["total"])
		self.assertEqual(sum(d["id_prefixes"].values()), d["total"])
		self.assertEqual(sum(d["versions"].values()), d["total"])

	def test_shape_detection(self):
		self.assertTrue(inv.shape_of('<div class="rh"></div>').startswith("B"))
		self.assertTrue(inv.shape_of('<table class="headerTable">').startswith("header table"))
		self.assertTrue(inv.shape_of("<div class=\"fontSize\">").startswith("other"))


if __name__ == "__main__":
	unittest.main()
