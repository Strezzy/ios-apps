// Three representative colors from a bounded, premultiplied RGBA thumbnail.
// Pure C so the color analysis can be checked independently of the iOS UI.
#ifndef MUSIC_ARTWORK_PALETTE
#define MUSIC_ARTWORK_PALETTE
static double GMPaletteMinimum(double a, double b) { return a < b ? a : b; }
static double GMPaletteMaximum(double a, double b) { return a > b ? a : b; }
static double GMPaletteDistance(const double a[3], const double b[3]) {
    double r=a[0]-b[0], g=a[1]-b[1], blue=a[2]-b[2];
    return r*r+g*g+blue*blue;
}
static double GMPalettePixel(const unsigned char *pixel, double rgb[3]) {
    if (pixel[3] < 32) return 0;
    double alpha = pixel[3]/255.0;
    for (unsigned c=0;c<3;c++) rgb[c]=GMPaletteMinimum(1,pixel[c]/(255.0*alpha));
    double high=GMPaletteMaximum(rgb[0],GMPaletteMaximum(rgb[1],rgb[2]));
    double low=GMPaletteMinimum(rgb[0],GMPaletteMinimum(rgb[1],rgb[2]));
    double saturation=high > .01 ? (high-low)/high : 0;
    double weight=alpha*(.3+.7*saturation);
    if (high < .07 || low > .94) weight *= .2;
    return weight;
}
static int GMExtractArtworkPalette(const unsigned char *pixels, unsigned count, double colors[3][3]) {
    if (!pixels || !colors || !count || count > 4096) return 0;
    double bins[512][4] = {{0}};
    double total=0;
    for (unsigned i=0;i<count;i++) {
        double rgb[3]; double weight=GMPalettePixel(pixels+i*4,rgb);
        if (weight <= 0) continue;
        unsigned key=((unsigned)(rgb[0]*7.999)<<6)|((unsigned)(rgb[1]*7.999)<<3)|(unsigned)(rgb[2]*7.999);
        bins[key][3]+=weight; total+=weight;
        for (unsigned c=0;c<3;c++) bins[key][c]+=rgb[c]*weight;
    }
    if (total <= 0) return 0;
    for (unsigned k=0;k<3;k++) {
        double best=-1; unsigned chosen=0;
        for (unsigned b=0;b<512;b++) {
            if (bins[b][3] <= 0) continue;
            double rgb[3]; for (unsigned c=0;c<3;c++) rgb[c]=bins[b][c]/bins[b][3];
            double distance=1;
            if (k) {
                distance=GMPaletteDistance(rgb,colors[0]);
                for (unsigned j=1;j<k;j++) distance=GMPaletteMinimum(distance,GMPaletteDistance(rgb,colors[j]));
            }
            double score=bins[b][3]*(k ? distance : 1);
            if (score > best) { best=score; chosen=b; }
        }
        for (unsigned c=0;c<3;c++) colors[k][c]=bins[chosen][c]/bins[chosen][3];
    }
    // Weighted clustering retains broad cover colors rather than isolated pixels.
    double finalWeights[3]={0,0,0};
    for (unsigned iteration=0;iteration<6;iteration++) {
        double sums[3][4]={{0}};
        for (unsigned b=0;b<512;b++) {
            if (bins[b][3] <= 0) continue;
            double rgb[3]; for (unsigned c=0;c<3;c++) rgb[c]=bins[b][c]/bins[b][3];
            unsigned nearest=0; double distance=GMPaletteDistance(rgb,colors[0]);
            for (unsigned k=1;k<3;k++) {
                double d=GMPaletteDistance(rgb,colors[k]);
                if (d < distance) { distance=d; nearest=k; }
            }
            for (unsigned c=0;c<4;c++) sums[nearest][c]+=bins[b][c];
        }
        for (unsigned k=0;k<3;k++) {
            finalWeights[k]=sums[k][3];
            if (sums[k][3]>0) for (unsigned c=0;c<3;c++) colors[k][c]=sums[k][c]/sums[k][3];
        }
    }
    for (unsigned a=0;a<3;a++) for (unsigned b=a+1;b<3;b++) if (finalWeights[b]>finalWeights[a]) {
        double weight=finalWeights[a]; finalWeights[a]=finalWeights[b]; finalWeights[b]=weight;
        for (unsigned c=0;c<3;c++) { double v=colors[a][c]; colors[a][c]=colors[b][c]; colors[b][c]=v; }
    }
    return 1;
}
#endif
