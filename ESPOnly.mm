// ESPOnly.mm - EDGY ESP (Lightweight + Full Feature)
// Only ESP, no anti-report, no DNS bypass, just pure ESP

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>

// ============================================
// DATA STRUCTURES
// ============================================
typedef struct { float x, y, z; } Vector3;

// ============================================
// OFFSETS (VALIDATED FOR CURRENT MLBB VERSION)
// ============================================
#define RVA_BATTLE_MANAGER_INST 0xADC8A0   
#define OFF_SHOW_PLAYERS        0x78        
#define OFF_SHOW_MONSTERS       0x80        
#define OFF_LOCAL_PLAYER        0x50        

#define OFF_ENTITY_POS          0x310       // IMPORTANT: 0x310 not 0x30!
#define OFF_ENTITY_CAMP         0xD8        
#define OFF_ENTITY_HP           0x1AC       
#define OFF_ENTITY_HP_MAX       0x1B0       
#define OFF_ENTITY_SHIELD       0x1B8       
#define OFF_PLAYER_HERO_NAME    0x918       
#define OFF_ENTITY_ID           0x194       

#define RVA_WORLD_TO_SCREEN     0x89FE040   
#define RVA_CAMERA_MAIN         0x89FF130   

// ============================================
// ESP SETTINGS (Bisa diubah manual di sini)
// ============================================
static BOOL espEnabled = NO;
static BOOL showEnemyBox = NO;
static BOOL showEnemyHp = NO;
static BOOL showEnemyName = NO;
static BOOL showEnemyLine = NO;
static BOOL showMonsterEsp = NO;
static BOOL showTeamEsp = NO;
static BOOL showDistance = NO;

// Warna ESP
static float enemyR = 1.0, enemyG = 0.2, enemyB = 0.2;   // Merah musuh
static float teamR = 0.2, teamG = 0.8, teamB = 0.2;      // Hijau tim
static float monsterR = 1.0, monsterG = 0.8, monsterB = 0.0; // Kuning monster

static uintptr_t g_unityBase = 0;

// ============================================
// UTILITIES
// ============================================

uintptr_t get_base(const char* name) {
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char* img = _dyld_get_image_name(i);
        if (img && strstr(img, name)) return (uintptr_t)_dyld_get_image_header(i);
    }
    return 0;
}

// Memory safety check for arm64 iOS
bool is_valid(uintptr_t ptr) {
    return (ptr > 0x100000000 && ptr < 0x2000000000 && (ptr & 0x3) == 0);
}

// Safe Il2Cpp string reader
NSString* readIl2CppString(uintptr_t ptr) {
    if (!is_valid(ptr)) return nil;
    int len = *(int*)(ptr + 0x10);
    if (len <= 0 || len > 64) return nil;
    uintptr_t dataPtr = ptr + 0x14;
    if (!is_valid(dataPtr)) return nil;
    return [NSString stringWithCharacters:(uint16_t*)dataPtr length:len];
}

// 3D Distance calculation
float distance3D(Vector3 a, Vector3 b) {
    float dx = a.x - b.x;
    float dy = a.y - b.y;
    float dz = a.z - b.z;
    return sqrtf(dx*dx + dy*dy + dz*dz);
}

// ============================================
// ESP RENDERER VIEW
// ============================================

@interface ESPOverlayView : UIView
@end

@implementation ESPOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.contentMode = UIViewContentModeRedraw;
        
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(redrawESP)];
        [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)redrawESP {
    if (espEnabled) [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    if (!espEnabled || !g_unityBase) return;
    
    @try {
        // Get BattleManager Instance
        uintptr_t bmAddr = *(uintptr_t*)(g_unityBase + RVA_BATTLE_MANAGER_INST);
        if (!is_valid(bmAddr)) return;
        uintptr_t bm = *(uintptr_t*)bmAddr;
        if (!is_valid(bm)) {
            bm = bmAddr;  // fallback
            if (!is_valid(bm)) return;
        }
        
        // Get Camera
        void* (*get_main)() = (void*(*)())(g_unityBase + RVA_CAMERA_MAIN);
        void* cam = get_main();
        if (!cam) return;
        
        // Get WorldToScreen function
        Vector3 (*w2s)(void*, Vector3) = (Vector3(*)(void*, Vector3))(g_unityBase + RVA_WORLD_TO_SCREEN);
        if (!w2s) return;
        
        // Get Local Player & Team
        uintptr_t localPlayer = *(uintptr_t*)(bm + OFF_LOCAL_PLAYER);
        int myTeam = (is_valid(localPlayer)) ? *(int*)(localPlayer + OFF_ENTITY_CAMP) : 0;
        Vector3 myPos = (is_valid(localPlayer)) ? *(Vector3*)(localPlayer + OFF_ENTITY_POS) : (Vector3){0,0,0};
        
        CGContextRef ctx = UIGraphicsGetCurrentContext();
        if (!ctx) return;
        
        CGContextSaveGState(ctx);
        
        // ========== DRAW PLAYERS ==========
        uintptr_t playerList = *(uintptr_t*)(bm + OFF_SHOW_PLAYERS);
        if (is_valid(playerList)) {
            uintptr_t playerArray = *(uintptr_t*)(playerList + 0x10);
            int playerCount = *(int*)(playerList + 0x18);
            
            if (playerCount > 0 && playerCount <= 60 && is_valid(playerArray)) {
                for (int i = 0; i < playerCount; i++) {
                    uintptr_t entity = *(uintptr_t*)(playerArray + 0x20 + (i * 8));
                    if (!is_valid(entity)) continue;
                    
                    int team = *(int*)(entity + OFF_ENTITY_CAMP);
                    
                    // Skip if same team and showTeamEsp is off
                    if (team == myTeam && !showTeamEsp) continue;
                    if (team == myTeam && showTeamEsp) {
                        // Draw team with green color
                        [self drawEntity:entity withCam:cam w2s:w2s ctx:ctx rect:rect 
                                    color:[UIColor colorWithRed:teamR green:teamG blue:teamB alpha:1.0] 
                                   isTeam:YES myPos:myPos];
                    } else if (team != myTeam) {
                        // Draw enemy with red color
                        [self drawEntity:entity withCam:cam w2s:w2s ctx:ctx rect:rect 
                                    color:[UIColor colorWithRed:enemyR green:enemyG blue:enemyB alpha:1.0] 
                                   isTeam:NO myPos:myPos];
                    }
                }
            }
        }
        
        // ========== DRAW MONSTERS ==========
        if (showMonsterEsp) {
            uintptr_t monsterList = *(uintptr_t*)(bm + OFF_SHOW_MONSTERS);
            if (is_valid(monsterList)) {
                uintptr_t monsterArray = *(uintptr_t*)(monsterList + 0x10);
                int monsterCount = *(int*)(monsterList + 0x18);
                
                if (monsterCount > 0 && monsterCount <= 30 && is_valid(monsterArray)) {
                    for (int i = 0; i < monsterCount; i++) {
                        uintptr_t entity = *(uintptr_t*)(monsterArray + 0x20 + (i * 8));
                        if (!is_valid(entity)) continue;
                        
                        // Filter important monsters (Lord, Turtle, Buff)
                        int m_id = *(int*)(entity + OFF_ENTITY_ID);
                        if (m_id == 1001 || m_id == 1002 || m_id == 2001 || m_id == 3001 || m_id == 3002) {
                            [self drawMonster:entity withCam:cam w2s:w2s ctx:ctx rect:rect 
                                         color:[UIColor colorWithRed:monsterR green:monsterG blue:monsterB alpha:1.0]
                                        myPos:myPos];
                        }
                    }
                }
            }
        }
        
        CGContextRestoreGState(ctx);
        
    } @catch (NSException *e) {
        // Silent fail, prevent crash
    }
}

- (void)drawEntity:(uintptr_t)entity withCam:(void*)cam w2s:(Vector3(*)(void*, Vector3))w2s 
               ctx:(CGContextRef)ctx rect:(CGRect)rect color:(UIColor*)color 
             isTeam:(BOOL)isTeam myPos:(Vector3)myPos {
    
    Vector3 pos = *(Vector3*)(entity + OFF_ENTITY_POS);
    Vector3 screenPos = w2s(cam, pos);
    
    if (screenPos.z < 1.0f) return; // Not visible
    
    float x = screenPos.x;
    float y = rect.size.height - screenPos.y;
    
    // Calculate box size based on distance
    float boxWidth = 800.0f / screenPos.z;
    float boxHeight = boxWidth * 1.3f;
    
    // Limit box size (no giant boxes)
    if (boxWidth > 180) boxWidth = 180;
    if (boxHeight > 234) boxHeight = 234;
    if (boxWidth < 30) boxWidth = 30;
    if (boxHeight < 39) boxHeight = 39;
    
    // 1. Draw ESP BOX (2D Rectangle)
    if (showEnemyBox) {
        CGContextSetStrokeColorWithColor(ctx, color.CGColor);
        CGContextSetLineWidth(ctx, 1.5);
        CGContextStrokeRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight, boxWidth, boxHeight));
        
        // Add corner decorations (makes it look pro)
        float cornerSize = boxWidth * 0.15;
        CGContextSetLineWidth(ctx, 2.0);
        // Top-left corner
        CGContextStrokeRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight, cornerSize, 2));
        CGContextStrokeRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight, 2, cornerSize));
        // Top-right corner
        CGContextStrokeRect(ctx, CGRectMake(x + boxWidth/2 - cornerSize, y - boxHeight, cornerSize, 2));
        CGContextStrokeRect(ctx, CGRectMake(x + boxWidth/2 - 2, y - boxHeight, 2, cornerSize));
        // Bottom-left corner
        CGContextStrokeRect(ctx, CGRectMake(x - boxWidth/2, y - 2, cornerSize, 2));
        CGContextStrokeRect(ctx, CGRectMake(x - boxWidth/2, y - cornerSize, 2, cornerSize));
        // Bottom-right corner
        CGContextStrokeRect(ctx, CGRectMake(x + boxWidth/2 - cornerSize, y - 2, cornerSize, 2));
        CGContextStrokeRect(ctx, CGRectMake(x + boxWidth/2 - 2, y - cornerSize, 2, cornerSize));
    }
    
    // 2. Draw SNAPLINE (from center to target)
    if (showEnemyLine) {
        CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.35].CGColor);
        CGContextSetLineWidth(ctx, 1.0);
        CGContextBeginPath(ctx);
        CGContextMoveToPoint(ctx, rect.size.width/2, rect.size.height/2);
        CGContextAddLineToPoint(ctx, x, y);
        CGContextStrokePath(ctx);
    }
    
    // 3. Draw HEALTH BAR
    if (showEnemyHp) {
        int hp = *(int*)(entity + OFF_ENTITY_HP);
        int maxHp = *(int*)(entity + OFF_ENTITY_HP_MAX);
        int shield = *(int*)(entity + OFF_ENTITY_SHIELD);
        float hpPercent = (float)hp / (float)maxHp;
        float shieldPercent = (float)shield / (float)maxHp;
        
        // Background bar
        CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.15 alpha:0.8].CGColor);
        CGContextFillRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight - 8, boxWidth, 4));
        
        // HP bar (green -> yellow -> red)
        UIColor *hpColor;
        if (hpPercent > 0.6) hpColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:1.0];
        else if (hpPercent > 0.3) hpColor = [UIColor yellowColor];
        else hpColor = [UIColor redColor];
        
        CGContextSetFillColorWithColor(ctx, hpColor.CGColor);
        CGContextFillRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight - 8, boxWidth * hpPercent, 4));
        
        // Shield bar (if exists)
        if (shield > 0 && shieldPercent > 0) {
            CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.85 alpha:0.9].CGColor);
            CGContextFillRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight - 8, boxWidth * MIN(shieldPercent, 1.0), 4));
        }
        
        // HP Text
        NSString *hpText = [NSString stringWithFormat:@"❤️ %d", hp];
        UIFont *hpFont = [UIFont boldSystemFontOfSize:10];
        NSDictionary *hpAttrs = @{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: hpFont};
        [hpText drawAtPoint:CGPointMake(x + boxWidth/2 + 3, y - boxHeight - 6) withAttributes:hpAttrs];
    }
    
    // 4. Draw HERO NAME
    if (showEnemyName && !isTeam) {
        uintptr_t namePtr = *(uintptr_t*)(entity + OFF_PLAYER_HERO_NAME);
        NSString *heroName = readIl2CppString(namePtr);
        if (heroName && heroName.length > 0) {
            UIFont *nameFont = [UIFont boldSystemFontOfSize:10];
            NSDictionary *nameAttrs = @{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: nameFont};
            CGSize nameSize = [heroName sizeWithAttributes:nameAttrs];
            [heroName drawAtPoint:CGPointMake(x - nameSize.width/2, y - boxHeight - 20) withAttributes:nameAttrs];
        }
    }
    
    // 5. Draw DISTANCE
    if (showDistance) {
        float dist = distance3D(myPos, pos);
        NSString *distText = [NSString stringWithFormat:@"%.0fｍ", dist];
        UIFont *distFont = [UIFont systemFontOfSize:9];
        NSDictionary *distAttrs = @{NSForegroundColorAttributeName: [UIColor colorWithWhite:0.8 alpha:1.0], NSFontAttributeName: distFont};
        [distText drawAtPoint:CGPointMake(x - boxWidth/2, y + 5) withAttributes:distAttrs];
    }
}

- (void)drawMonster:(uintptr_t)entity withCam:(void*)cam w2s:(Vector3(*)(void*, Vector3))w2s 
                ctx:(CGContextRef)ctx rect:(CGRect)rect color:(UIColor*)color myPos:(Vector3)myPos {
    
    Vector3 pos = *(Vector3*)(entity + OFF_ENTITY_POS);
    Vector3 screenPos = w2s(cam, pos);
    
    if (screenPos.z < 1.0f) return;
    
    float x = screenPos.x;
    float y = rect.size.height - screenPos.y;
    float boxWidth = 600.0f / screenPos.z;
    float boxHeight = boxWidth * 1.2f;
    
    if (boxWidth > 150) boxWidth = 150;
    if (boxHeight > 180) boxHeight = 180;
    if (boxWidth < 25) boxWidth = 25;
    
    // Monster Box
    CGContextSetStrokeColorWithColor(ctx, color.CGColor);
    CGContextSetLineWidth(ctx, 1.5);
    CGContextStrokeRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight, boxWidth, boxHeight));
    
    // Monster HP
    int hp = *(int*)(entity + OFF_ENTITY_HP);
    int maxHp = *(int*)(entity + OFF_ENTITY_HP_MAX);
    float hpPercent = (float)hp / (float)maxHp;
    
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:0.15 alpha:0.8].CGColor);
    CGContextFillRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight - 6, boxWidth, 3));
    CGContextSetFillColorWithColor(ctx, color.CGColor);
    CGContextFillRect(ctx, CGRectMake(x - boxWidth/2, y - boxHeight - 6, boxWidth * hpPercent, 3));
    
    // Monster Name based on ID
    int m_id = *(int*)(entity + OFF_ENTITY_ID);
    NSString *monsterName = @"🐉 MONSTER";
    if (m_id == 1001 || m_id == 1002) monsterName = @"👑 LORD";
    else if (m_id == 2001) monsterName = @"🐢 TURTLE";
    else if (m_id == 3001 || m_id == 3002) monsterName = @"💀 BUFF";
    
    UIFont *nameFont = [UIFont boldSystemFontOfSize:9];
    NSDictionary *attrs = @{NSForegroundColorAttributeName: [UIColor whiteColor], NSFontAttributeName: nameFont};
    [monsterName drawAtPoint:CGPointMake(x - 30, y - boxHeight - 15) withAttributes:attrs];
}

@end

// ============================================
// SIMPLE MENU MANAGER
// ============================================

@interface ESPMenuManager : NSObject
@property (nonatomic, strong) UIButton *fab;
@property (nonatomic, strong) UIView *menuPanel;
@property (nonatomic, assign) BOOL isMenuVisible;
+ (instancetype)shared;
- (void)setupWithWindow:(UIWindow *)window;
- (void)toggleMenu;
- (void)updateSwitch:(UISwitch *)sender;
@end

@implementation ESPMenuManager

+ (instancetype)shared {
    static ESPMenuManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (void)setupWithWindow:(UIWindow *)window {
    // Floating Action Button
    self.fab = [UIButton buttonWithType:UIButtonTypeCustom];
    self.fab.frame = CGRectMake(15, 120, 55, 55);
    self.fab.backgroundColor = [UIColor colorWithRed:0.1 green:0.2 blue:0.5 alpha:0.95];
    self.fab.layer.cornerRadius = 27.5;
    self.fab.layer.shadowColor = [UIColor cyanColor].CGColor;
    self.fab.layer.shadowOffset = CGSizeMake(0, 0);
    self.fab.layer.shadowOpacity = 0.6;
    self.fab.layer.shadowRadius = 4;
    [self.fab setTitle:@"ESP" forState:UIControlStateNormal];
    self.fab.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.fab addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.fab addGestureRecognizer:pan];
    [window addSubview:self.fab];
    
    // ESP Overlay
    ESPOverlayView *espView = [[ESPOverlayView alloc] initWithFrame:window.bounds];
    [window addSubview:espView];
}

- (void)handlePan:(UIPanGestureRecognizer *)p {
    CGPoint translation = [p translationInView:self.fab.superview];
    self.fab.center = CGPointMake(self.fab.center.x + translation.x, self.fab.center.y + translation.y);
    [p setTranslation:CGPointZero inView:self.fab.superview];
}

- (void)toggleMenu {
    if (!self.menuPanel) {
        [self createMenu];
    }
    self.menuPanel.hidden = !self.menuPanel.hidden;
}

- (void)createMenu {
    UIWindow *window = self.fab.superview;
    if (!window) return;
    
    self.menuPanel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 260, 380)];
    self.menuPanel.center = window.center;
    self.menuPanel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
    self.menuPanel.layer.cornerRadius = 18;
    self.menuPanel.layer.borderWidth = 1.5;
    self.menuPanel.layer.borderColor = [UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1.0].CGColor;
    self.menuPanel.layer.shadowColor = [UIColor blackColor].CGColor;
    self.menuPanel.layer.shadowOffset = CGSizeMake(0, 2);
    self.menuPanel.layer.shadowOpacity = 0.5;
    self.menuPanel.layer.shadowRadius = 8;
    
    // Title with close button
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 12, 260, 28)];
    title.text = @"⚡ EDGY ESP ⚡";
    title.textColor = [UIColor cyanColor];
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont boldSystemFontOfSize:17];
    [self.menuPanel addSubview:title];
    
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(215, 12, 35, 28);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [closeBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [self.menuPanel addSubview:closeBtn];
    
    // Separator
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(15, 48, 230, 0.5)];
    sep.backgroundColor = [UIColor grayColor];
    [self.menuPanel addSubview:sep];
    
    // Helper to add toggle
    __weak typeof(self) weakSelf = self;
    auto addToggle = ^(NSString *title, BOOL *value, int yOffset) {
        UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(20, yOffset, 160, 32)];
        lbl.text = title;
        lbl.textColor = [UIColor whiteColor];
        lbl.font = [UIFont systemFontOfSize:14];
        [weakSelf.menuPanel addSubview:lbl];
        
        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(190, yOffset, 50, 32)];
        sw.on = *value;
        sw.onTintColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:1.0];
        objc_setAssociatedObject(sw, "valuePtr", [NSValue valueWithPointer:value], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [sw addTarget:weakSelf action:@selector(updateSwitch:) forControlEvents:UIControlEventValueChanged];
        [weakSelf.menuPanel addSubview:sw];
    };
    
    addToggle(@"🎯 ESP MASTER", &espEnabled, 60);
    addToggle(@"📦 Enemy Box", &showEnemyBox, 100);
    addToggle(@"❤️ Enemy HP", &showEnemyHp, 140);
    addToggle(@"🏷️ Enemy Name", &showEnemyName, 180);
    addToggle(@"📏 Distance", &showDistance, 220);
    addToggle(@"🔗 Snapline", &showEnemyLine, 260);
    addToggle(@"👥 Show Team", &showTeamEsp, 300);
    addToggle(@"🐉 Monster ESP", &showMonsterEsp, 340);
    
    [window addSubview:self.menuPanel];
}

- (void)updateSwitch:(UISwitch *)sender {
    NSValue *val = objc_getAssociatedObject(sender, "valuePtr");
    BOOL *ptr = (BOOL *)[val pointerValue];
    if (ptr) *ptr = sender.on;
}

@end

// ============================================
// INITIALIZATION
// ============================================

__attribute__((constructor))
static void initializeESP() {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        g_unityBase = get_base("UnityFramework");
        if (g_unityBase) {
            UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
            if (!keyWindow) {
                keyWindow = [UIApplication sharedApplication].windows.firstObject;
            }
            if (keyWindow) {
                [[ESPMenuManager shared] setupWithWindow:keyWindow];
            }
        }
    });
}