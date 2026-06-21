/* ImageProcessor 空实现 stub — 闭源 libImageProcessor.so 仅 x86 有，aarch64 无
 * 不改 HPCupsFilter.cpp 避免破坏 C++ 结构，用空 .a 满足链接器
 * 所有函数返回 IPE_SUCCESS，运行时不会被调用（我们的打印机不走 ljzjstream 分支） */

typedef unsigned char BYTE;

typedef struct _image_processor_handle image_processor_t;

typedef enum {
    IPE_SUCCESS = 0
} IMAGE_PROCESSOR_ERROR;

typedef struct {
    unsigned cupsBytesPerLine;
} cups_page_header2_t;

image_processor_t* imageProcessorCreate(void) {
    return (image_processor_t*)1;
}

void imageProcessorDestroy(image_processor_t* p) {
    (void)p;
}

IMAGE_PROCESSOR_ERROR imageProcessorStartPage(image_processor_t* p, cups_page_header2_t* h) {
    (void)p;
    (void)h;
    return IPE_SUCCESS;
}

IMAGE_PROCESSOR_ERROR imageProcessorProcessLine(image_processor_t* p, BYTE* buf, unsigned sz) {
    (void)p;
    (void)buf;
    (void)sz;
    return IPE_SUCCESS;
}

IMAGE_PROCESSOR_ERROR imageProcessorEndPage(image_processor_t* p) {
    (void)p;
    return IPE_SUCCESS;
}
