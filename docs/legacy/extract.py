import zipfile
import xml.etree.ElementTree as ET
import glob
import os

def extract_text_from_docx(docx_path):
    try:
        with zipfile.ZipFile(docx_path, 'r') as docx:
            xml_content = docx.read('word/document.xml')
            tree = ET.fromstring(xml_content)
            ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
            text = []
            for paragraph in tree.findall('.//w:p', ns):
                para_text = []
                for run in paragraph.findall('.//w:r', ns):
                    for t in run.findall('.//w:t', ns):
                        if t.text:
                            para_text.append(t.text)
                text.append(''.join(para_text))
            return '\n'.join(text)
    except Exception as e:
        return str(e)

if __name__ == '__main__':
    with open('extracted_texts.txt', 'w', encoding='utf-8') as f:
        for doc in glob.glob('*.docx'):
            f.write(f"--- {doc} ---\n")
            f.write(extract_text_from_docx(doc))
            f.write("\n\n")
