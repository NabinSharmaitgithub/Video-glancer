#!/bin/bash

# Video to Screenshot PDF Converter Setup Script
# This script will:
# 1. Install required dependencies
# 2. Create the project structure
# 3. Set up the virtual environment
# 4. Configure the Flask application

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${YELLOW}Warning: Running as root. It's recommended to run this as a regular user.${NC}"
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check for Python 3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Python 3 is required but not installed. Please install Python 3 first.${NC}"
    exit 1
fi

# Check for pip
if ! command -v pip3 &> /dev/null; then
    echo -e "${RED}pip3 is required but not installed. Please install pip3 first.${NC}"
    exit 1
fi

# Project name and directory
PROJECT_NAME="video_to_pdf_app"
PROJECT_DIR="$PWD/$PROJECT_NAME"

echo -e "${GREEN}Setting up Video to Screenshot PDF Converter...${NC}"

# Create project directory
echo -e "${YELLOW}Creating project directory...${NC}"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR" || exit

# Create directory structure
echo -e "${YELLOW}Creating directory structure...${NC}"
mkdir -p {templates,static,uploads,screenshots}

# Create virtual environment
echo -e "${YELLOW}Setting up Python virtual environment...${NC}"
python3 -m venv venv
source venv/bin/activate

# Install dependencies
echo -e "${YELLOW}Installing Python dependencies...${NC}"
pip install --upgrade pip
pip install flask opencv-python fpdf2 requests werkzeug

# Create app.py
echo -e "${YELLOW}Creating Flask application file...${NC}"
cat > app.py << 'EOL'
import os
import cv2
import requests
import tempfile
from flask import Flask, render_template, request, send_file, redirect, url_for, flash
from fpdf import FPDF
from datetime import datetime
from werkzeug.utils import secure_filename
from urllib.parse import urlparse

app = Flask(__name__)
app.secret_key = 'your-secret-key-here'  # Change this for production
app.config['UPLOAD_FOLDER'] = 'uploads'
app.config['SCREENSHOT_FOLDER'] = 'screenshots'
app.config['ALLOWED_EXTENSIONS'] = {'mp4', 'avi', 'mov', 'mkv'}
app.config['MAX_CONTENT_LENGTH'] = 100 * 1024 * 1024  # 100MB limit

# Ensure upload directories exist
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
os.makedirs(app.config['SCREENSHOT_FOLDER'], exist_ok=True)

def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in app.config['ALLOWED_EXTENSIONS']

def is_valid_url(url):
    try:
        result = urlparse(url)
        return all([result.scheme, result.netloc])
    except ValueError:
        return False

def download_video_from_url(url):
    try:
        headers = {'User-Agent': 'Mozilla/5.0'}
        response = requests.get(url, stream=True, headers=headers)
        response.raise_for_status()
        
        # Create a temporary file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.mp4')
        
        # Write the content to the temporary file
        for chunk in response.iter_content(chunk_size=8192):
            if chunk:
                temp_file.write(chunk)
        
        temp_file.close()
        return temp_file.name
    except Exception as e:
        print(f"Error downloading video: {e}")
        return None

def create_pdf_from_screenshots(screenshot_paths, output_pdf):
    if not screenshot_paths:
        return False

    # Determine PDF page size based on first image
    first_img = cv2.imread(screenshot_paths[0])
    img_height, img_width = first_img.shape[:2]
    
    # Convert from pixels to mm (assuming 96 dpi)
    mm_width = img_width * 25.4 / 96
    mm_height = img_height * 25.4 / 96
    
    pdf = FPDF(unit="mm", format=(mm_width, mm_height))
    pdf.set_auto_page_break(False)
    
    for img_path in screenshot_paths:
        pdf.add_page()
        pdf.image(img_path, x=0, y=0, w=mm_width, h=mm_height)
    
    pdf.output(output_pdf)
    return True

def process_video(video_path, interval, timestamp):
    try:
        # Generate output names
        output_pdf = f"video_screenshots_{timestamp}.pdf"
        pdf_path = os.path.join(app.config['SCREENSHOT_FOLDER'], output_pdf)
        
        # Process video
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            return None, "Could not open video file"
        
        fps = cap.get(cv2.CAP_PROP_FPS)
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        frame_interval = int(fps * interval)
        
        screenshot_paths = []
        frame_count = 0
        screenshot_num = 0
        
        while True:
            ret, frame = cap.read()
            if not ret:
                break
                
            if frame_count % frame_interval == 0:
                screenshot_path = os.path.join(
                    app.config['SCREENSHOT_FOLDER'],
                    f"screenshot_{timestamp}_{screenshot_num:04d}.jpg"
                )
                cv2.imwrite(screenshot_path, frame)
                screenshot_paths.append(screenshot_path)
                screenshot_num += 1
                
            frame_count += 1
        
        cap.release()
        
        # Create PDF
        if create_pdf_from_screenshots(screenshot_paths, pdf_path):
            # Clean up screenshots
            for img_path in screenshot_paths:
                os.remove(img_path)
            
            return output_pdf, None
        else:
            return None, "Failed to create PDF"
    except Exception as e:
        return None, str(e)

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        # Get interval from form (default to 10 seconds)
        try:
            interval = int(request.form.get('interval', 10))
        except ValueError:
            interval = 10
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Check if URL was provided
        video_url = request.form.get('video_url', '').strip()
        if video_url:
            if not is_valid_url(video_url):
                flash('Please enter a valid video URL', 'error')
                return redirect(request.url)
            
            # Download video from URL
            temp_video_path = download_video_from_url(video_url)
            if not temp_video_path:
                flash('Failed to download video from URL', 'error')
                return redirect(request.url)
            
            # Process the downloaded video
            output_pdf, error = process_video(temp_video_path, interval, timestamp)
            
            # Clean up temporary video file
            if os.path.exists(temp_video_path):
                os.remove(temp_video_path)
            
            if error:
                flash(error, 'error')
                return redirect(request.url)
            
            return redirect(url_for('download', filename=output_pdf))
        
        # Check for file upload
        elif 'file' in request.files:
            file = request.files['file']
            if file.filename == '':
                flash('No file selected', 'error')
                return redirect(request.url)
            
            if file and allowed_file(file.filename):
                # Save uploaded file
                filename = secure_filename(file.filename)
                video_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
                file.save(video_path)
                
                # Process the video
                output_pdf, error = process_video(video_path, interval, timestamp)
                
                # Clean up uploaded video file
                if os.path.exists(video_path):
                    os.remove(video_path)
                
                if error:
                    flash(error, 'error')
                    return redirect(request.url)
                
                return redirect(url_for('download', filename=output_pdf))
            else:
                flash('Invalid file type. Allowed formats: MP4, AVI, MOV, MKV', 'error')
                return redirect(request.url)
        else:
            flash('Please provide either a video file or URL', 'error')
            return redirect(request.url)
    
    return render_template('index.html')

@app.route('/download/<filename>')
def download(filename):
    return send_file(
        os.path.join(app.config['SCREENSHOT_FOLDER'], filename),
        as_attachment=True,
        download_name=filename
    )

if __name__ == '__main__':
    app.run(debug=True)
EOL

# Create templates/index.html
echo -e "${YELLOW}Creating HTML template...${NC}"
cat > templates/index.html << 'EOL'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Video to Screenshot PDF Converter</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            line-height: 1.6;
        }
        .container {
            background-color: #f9f9f9;
            border-radius: 8px;
            padding: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            text-align: center;
        }
        .form-group {
            margin-bottom: 15px;
        }
        label {
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
        }
        input[type="file"] {
            width: 100%;
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 4px;
        }
        input[type="number"], input[type="url"] {
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
            width: 100%;
            box-sizing: border-box;
        }
        input[type="number"] {
            width: 100px;
        }
        button {
            background-color: #4CAF50;
            color: white;
            padding: 10px 15px;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 16px;
            width: 100%;
            margin-top: 10px;
        }
        button:hover {
            background-color: #45a049;
        }
        .error {
            color: red;
            margin-bottom: 15px;
            padding: 10px;
            background-color: #ffeeee;
            border-radius: 4px;
        }
        .success {
            color: green;
            margin-bottom: 15px;
            padding: 10px;
            background-color: #eeffee;
            border-radius: 4px;
        }
        .tabs {
            display: flex;
            margin-bottom: 20px;
        }
        .tab {
            padding: 10px 20px;
            cursor: pointer;
            background-color: #eee;
            border-radius: 4px 4px 0 0;
            margin-right: 5px;
        }
        .tab.active {
            background-color: #4CAF50;
            color: white;
        }
        .tab-content {
            display: none;
        }
        .tab-content.active {
            display: block;
        }
        .info {
            margin-top: 20px;
            padding: 15px;
            background-color: #f0f8ff;
            border-radius: 4px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Video to Screenshot PDF Converter</h1>
        
        {% with messages = get_flashed_messages(with_categories=true) %}
            {% if messages %}
                {% for category, message in messages %}
                    <div class="{{ category }}">{{ message }}</div>
                {% endfor %}
            {% endif %}
        {% endwith %}
        
        <div class="tabs">
            <div class="tab active" onclick="switchTab('upload')">File Upload</div>
            <div class="tab" onclick="switchTab('url')">Video URL</div>
        </div>
        
        <form method="POST" enctype="multipart/form-data">
            <div class="tab-content active" id="upload-tab">
                <div class="form-group">
                    <label for="file">Select Video File:</label>
                    <input type="file" id="file" name="file" accept="video/*">
                </div>
            </div>
            
            <div class="tab-content" id="url-tab">
                <div class="form-group">
                    <label for="video_url">Enter Video URL:</label>
                    <input type="url" id="video_url" name="video_url" placeholder="https://example.com/video.mp4">
                </div>
            </div>
            
            <div class="form-group">
                <label for="interval">Screenshot Interval (seconds):</label>
                <input type="number" id="interval" name="interval" value="10" min="1" required>
            </div>
            
            <button type="submit">Convert to PDF</button>
        </form>
        
        <div class="info">
            <h3>How it works:</h3>
            <ol>
                <li>Upload a video file or provide a video URL</li>
                <li>Set the interval between screenshots (default: 10 seconds)</li>
                <li>Click "Convert to PDF"</li>
                <li>Download your PDF with screenshots</li>
            </ol>
            
            <p>Supported video formats: MP4, AVI, MOV, MKV</p>
            <p>Maximum file size: 100MB (for uploads)</p>
        </div>
    </div>

    <script>
        function switchTab(tabName) {
            // Hide all tab contents
            document.querySelectorAll('.tab-content').forEach(content => {
                content.classList.remove('active');
            });
            
            // Show selected tab content
            document.getElementById(tabName + '-tab').classList.add('active');
            
            // Update tab styling
            document.querySelectorAll('.tab').forEach(tab => {
                tab.classList.remove('active');
            });
            event.currentTarget.classList.add('active');
        }
    </script>
</body>
</html>
EOL

# Create a run script
echo -e "${YELLOW}Creating run script...${NC}"
cat > run.sh << 'EOL'
#!/bin/bash

# Run the Video to Screenshot PDF Converter

# Activate virtual environment
source venv/bin/activate

# Run the Flask application
python app.py
EOL

chmod +x run.sh

# Create a requirements file
echo -e "${YELLOW}Creating requirements file...${NC}"
pip freeze > requirements.txt

# Instructions
echo -e "${GREEN}Setup complete!${NC}"
echo -e "To run the application:"
echo -e "1. Change to the project directory: ${YELLOW}cd $PROJECT_DIR${NC}"
echo -e "2. Start the application: ${YELLOW}./run.sh${NC}"
echo -e "3. Open your browser to: ${YELLOW}http://localhost:5000${NC}"

exit 0
