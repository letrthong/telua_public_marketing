import sys
import os
import logging

# Cấu hình logging để hiển thị thông tin chi tiết
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# Thêm đường dẫn hiện tại vào sys.path để import module cùng thư mục
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.append(current_dir)

try:
    import telua_chatbot
except ImportError:
    print("Lỗi: Không thể import 'telua_chatbot'. Hãy đảm bảo file này nằm cùng thư mục với telua_chatbot.py")
    sys.exit(1)

def run_tests():
    print("\n" + "="*50)
    print("BẮT ĐẦU KIỂM TRA CHATBOT (telua_chatbot.py)")
    print("="*50 + "\n")

    # --- Test Case 1: Chat thông thường ---
    print("[TEST 1] Kiểm tra hàm generate_response(prompt)")
    test_prompt = "Xin chào, hãy liệt kê các sản phẩm đang có trong hệ thống."
    print(f"Input Prompt: '{test_prompt}'")
    print("-" * 20)
    
    response = telua_chatbot.generate_response(test_prompt)
    print(f"Output Response:\n{response}")
    print("\n" + "-"*50 + "\n")

    # --- Test Case 2: Tạo báo cáo ---
    print("[TEST 2] Kiểm tra hàm generate_report_response(topic)")
    test_topic = "Phân tích danh mục sản phẩm"
    print(f"Input Topic: '{test_topic}'")
    print("-" * 20)

    report = telua_chatbot.generate_report_response(test_topic)
    print(f"Output Report:\n{report}")
    
    print("\n" + "="*50)
    print("HOÀN THÀNH KIỂM TRA")
    print("="*50)

if __name__ == "__main__":
    run_tests()