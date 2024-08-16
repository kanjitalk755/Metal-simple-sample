#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <simd/simd.h>

#define VSYNC	0
#define TRI_N	1000

struct Prim {
	simd_float2 position;
	float hue, angle;
};

struct Vtx {
	simd_float2 position;
	simd_float4 color;
};

static struct Triangle {
	void init(CGSize size) {
		if (!inited) {
			srandomdev();
			inited = true;
		}
		x = .5 * size.width;
		y = .5 * size.height;
		float t = 2 * M_PI * random() / INT_MAX;
		xs = cosf(t);
		ys = sinf(t);
		hue = t;
		angle = 0;
		omega = (.2 * random() / INT_MAX) - .1;
	}
	void update(CGSize size, Prim &pt) {
		x += xs;
		if (x < 0) xs = fabsf(xs);
		else if (x > size.width) xs = -fabsf(xs);
		y += ys;
		if (y < 0) ys = fabsf(ys);
		else if (y > size.height) ys = -fabsf(ys);
		pt.position = simd_make_float2(x, y);
		pt.angle = angle += omega;
		pt.hue = hue += .01;
	}
	inline static bool inited;
	float x, y, xs, ys, angle, omega, hue;
} tri[TRI_N];

@interface ViewController : NSViewController
@end

@implementation ViewController {
	id<MTLDevice> _device;
	id<MTLBuffer> _vtxBuf, _sizeBuf;
	id<MTLCommandQueue> _commandQueue;
	id<MTLComputePipelineState> _computePipeline;
	id<MTLRenderPipelineState> _renderPipeline;
	CAMetalLayer *_metalLayer;
	NSTimer *_timer;
}

- (void)viewDidLoad {
	[super viewDidLoad];

	assert(_device = MTLCreateSystemDefaultDevice());
	_commandQueue = [_device newCommandQueue];
	id<MTLLibrary> lib = [_device newDefaultLibrary];
	
	id<MTLFunction> func = [lib newFunctionWithName:@"geometryShader"];
	_computePipeline = [_device newComputePipelineStateWithFunction:func error:nil];

	MTLRenderPipelineDescriptor *renderPipelineDesc = [MTLRenderPipelineDescriptor new];
	renderPipelineDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
	[renderPipelineDesc setVertexFunction:[lib newFunctionWithName:@"VertexShader"]];
	[renderPipelineDesc setFragmentFunction:[lib newFunctionWithName:@"FragmentShader"]];
	_renderPipeline = [_device newRenderPipelineStateWithDescriptor:renderPipelineDesc error:nil];
	
	const CGSize size = self.view.bounds.size;
	simd_float2 t = simd_make_float2(size.width, size.height);
	_sizeBuf= [_device newBufferWithBytes:&t length:sizeof(simd_float2) options:MTLResourceStorageModeShared];
	_vtxBuf = [_device newBufferWithLength:3 * TRI_N * sizeof(Vtx) options:MTLResourceStorageModePrivate];

	self.view.wantsLayer = YES;

	_metalLayer = [CAMetalLayer layer];
	_metalLayer.device = _device;
	_metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
	_metalLayer.framebufferOnly = YES;
	_metalLayer.frame = self.view.layer.frame;
	_metalLayer.drawableSize = size;
	_metalLayer.displaySyncEnabled = VSYNC ? YES : NO;
	[self.view.layer addSublayer: _metalLayer];
	
	_timer = [NSTimer scheduledTimerWithTimeInterval:VSYNC ? 0. : 1. / 60. target:self selector:@selector(render) userInfo:nil repeats:YES];
	
	for (int i = 0; i < TRI_N; i++)
		tri[i].init(size);
}

- (void)render {
	id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
	if (!drawable) return;

	Prim prim[TRI_N];
	for (int i = 0; i < TRI_N; i++)
		tri[i].update(_metalLayer.drawableSize, prim[i]);
	id<MTLBuffer> geoBuf= [_device newBufferWithBytes:&prim length:sizeof(prim) options:MTLResourceStorageModeShared];

	id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
	
	id<MTLComputeCommandEncoder> computeCmd = [cmdBuf computeCommandEncoder];
	[computeCmd setComputePipelineState:_computePipeline];
	[computeCmd setBuffer:geoBuf offset:0 atIndex:0];
	[computeCmd setBuffer:_vtxBuf offset:0 atIndex:1];
	[computeCmd dispatchThreadgroups:MTLSizeMake(1, 1, 1) threadsPerThreadgroup:MTLSizeMake(TRI_N, 1, 1)];
	[computeCmd endEncoding];

	MTLRenderPassDescriptor *renderPassDesc = [MTLRenderPassDescriptor renderPassDescriptor];
	renderPassDesc.colorAttachments[0].texture = drawable.texture;
	renderPassDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
	renderPassDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
	renderPassDesc.colorAttachments[0].clearColor = MTLClearColorMake(.5, .5, .5, 1);
	
	id<MTLRenderCommandEncoder> renderCmd = [cmdBuf renderCommandEncoderWithDescriptor:renderPassDesc];
	[renderCmd setViewport:(MTLViewport){ 0, 0, _metalLayer.drawableSize.width, _metalLayer.drawableSize.height, 0, 1 }];
	[renderCmd setRenderPipelineState:_renderPipeline];
	[renderCmd setVertexBuffer:_vtxBuf offset:0 atIndex:0];
	[renderCmd setVertexBuffer:_sizeBuf offset:0 atIndex:1];
	[renderCmd drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3 * TRI_N];
	[renderCmd endEncoding];
	
	[cmdBuf presentDrawable:drawable];
	[cmdBuf commit];
}

- (void)dealloc {
	[_timer invalidate];
}

@end
