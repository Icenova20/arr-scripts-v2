from http.server import HTTPServer, BaseHTTPRequestHandler
import json

class SonarrMock(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/api/v3/series/"):
            # Individual series
            series_id = self.path.split("/")[4].split("?")[0]
            data = {
                "id": int(series_id),
                "title": f"Series {series_id}",
                "seriesType": "standard",
                "tags": [1, 2, 3]
            }
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())
        elif self.path.startswith("/api/v3/series"):
            # All series
            data = [{"id": i} for i in range(1, 101)] # 100 series
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())
        elif self.path.startswith("/api/v3/tag/"):
            # Individual tag
            tag_id = self.path.split("/")[4].split("?")[0]
            data = {"id": int(tag_id), "label": "daily" if int(tag_id) == 2 else "other"}
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())
        elif self.path.startswith("/api/v3/tag"):
            # All tags
            data = [
                {"id": 1, "label": "other"},
                {"id": 2, "label": "daily"},
                {"id": 3, "label": "another"}
            ]
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(data).encode())
        else:
            self.send_response(404)
            self.end_headers()

httpd = HTTPServer(('localhost', 8989), SonarrMock)
httpd.serve_forever()
