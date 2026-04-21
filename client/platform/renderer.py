class Renderer:
    def clear(self, color):
        raise NotImplementedError

    def fill_rect(self, x, y, w, h, color):
        raise NotImplementedError

    def draw_text(self, x, y, text, color):
        raise NotImplementedError

    def draw_image(self, asset_path, x, y):
        raise NotImplementedError

    def draw_atlas(self, asset_path, atlas_index, x, y):
        raise NotImplementedError

    def present(self):
        pass
