(function dartProgram(){function copyProperties(a,b){var s=Object.keys(a)
for(var r=0;r<s.length;r++){var q=s[r]
b[q]=a[q]}}function mixinPropertiesHard(a,b){var s=Object.keys(a)
for(var r=0;r<s.length;r++){var q=s[r]
if(!b.hasOwnProperty(q)){b[q]=a[q]}}}function mixinPropertiesEasy(a,b){Object.assign(b,a)}var z=function(){var s=function(){}
s.prototype={p:{}}
var r=new s()
if(!(Object.getPrototypeOf(r)&&Object.getPrototypeOf(r).p===s.prototype.p))return false
try{if(typeof navigator!="undefined"&&typeof navigator.userAgent=="string"&&navigator.userAgent.indexOf("Chrome/")>=0)return true
if(typeof version=="function"&&version.length==0){var q=version()
if(/^\d+\.\d+\.\d+\.\d+$/.test(q))return true}}catch(p){}return false}()
function inherit(a,b){a.prototype.constructor=a
a.prototype["$i"+a.name]=a
if(b!=null){if(z){Object.setPrototypeOf(a.prototype,b.prototype)
return}var s=Object.create(b.prototype)
copyProperties(a.prototype,s)
a.prototype=s}}function inheritMany(a,b){for(var s=0;s<b.length;s++){inherit(b[s],a)}}function mixinEasy(a,b){mixinPropertiesEasy(b.prototype,a.prototype)
a.prototype.constructor=a}function mixinHard(a,b){mixinPropertiesHard(b.prototype,a.prototype)
a.prototype.constructor=a}function lazy(a,b,c,d){var s=a
a[b]=s
a[c]=function(){if(a[b]===s){a[b]=d()}a[c]=function(){return this[b]}
return a[b]}}function lazyFinal(a,b,c,d){var s=a
a[b]=s
a[c]=function(){if(a[b]===s){var r=d()
if(a[b]!==s){A.n0(b)}a[b]=r}var q=a[b]
a[c]=function(){return q}
return q}}function makeConstList(a,b){if(b!=null)A.x(a,b)
a.$flags=7
return a}function convertToFastObject(a){function t(){}t.prototype=a
new t()
return a}function convertAllToFastObject(a){for(var s=0;s<a.length;++s){convertToFastObject(a[s])}}var y=0
function instanceTearOffGetter(a,b){var s=null
return a?function(c){if(s===null)s=A.i5(b)
return new s(c,this)}:function(){if(s===null)s=A.i5(b)
return new s(this,null)}}function staticTearOffGetter(a){var s=null
return function(){if(s===null)s=A.i5(a).prototype
return s}}var x=0
function tearOffParameters(a,b,c,d,e,f,g,h,i,j){if(typeof h=="number"){h+=x}return{co:a,iS:b,iI:c,rC:d,dV:e,cs:f,fs:g,fT:h,aI:i||0,nDA:j}}function installStaticTearOff(a,b,c,d,e,f,g,h){var s=tearOffParameters(a,true,false,c,d,e,f,g,h,false)
var r=staticTearOffGetter(s)
a[b]=r}function installInstanceTearOff(a,b,c,d,e,f,g,h,i,j){c=!!c
var s=tearOffParameters(a,false,c,d,e,f,g,h,i,!!j)
var r=instanceTearOffGetter(c,s)
a[b]=r}function setOrUpdateInterceptorsByTag(a){var s=v.interceptorsByTag
if(!s){v.interceptorsByTag=a
return}copyProperties(a,s)}function setOrUpdateLeafTags(a){var s=v.leafTags
if(!s){v.leafTags=a
return}copyProperties(a,s)}function updateTypes(a){var s=v.types
var r=s.length
s.push.apply(s,a)
return r}function updateHolder(a,b){copyProperties(b,a)
return a}var hunkHelpers=function(){var s=function(a,b,c,d,e){return function(f,g,h,i){return installInstanceTearOff(f,g,a,b,c,d,[h],i,e,false)}},r=function(a,b,c,d){return function(e,f,g,h){return installStaticTearOff(e,f,a,b,c,[g],h,d)}}
return{inherit:inherit,inheritMany:inheritMany,mixin:mixinEasy,mixinHard:mixinHard,installStaticTearOff:installStaticTearOff,installInstanceTearOff:installInstanceTearOff,_instance_0u:s(0,0,null,["$0"],0),_instance_1u:s(0,1,null,["$1"],0),_instance_2u:s(0,2,null,["$2"],0),_instance_0i:s(1,0,null,["$0"],0),_instance_1i:s(1,1,null,["$1"],0),_instance_2i:s(1,2,null,["$2"],0),_static_0:r(0,null,["$0"],0),_static_1:r(1,null,["$1"],0),_static_2:r(2,null,["$2"],0),makeConstList:makeConstList,lazy:lazy,lazyFinal:lazyFinal,updateHolder:updateHolder,convertToFastObject:convertToFastObject,updateTypes:updateTypes,setOrUpdateInterceptorsByTag:setOrUpdateInterceptorsByTag,setOrUpdateLeafTags:setOrUpdateLeafTags}}()
function initializeDeferredHunk(a){x=v.types.length
a(hunkHelpers,v,w,$)}var J={
ia(a,b,c,d){return{i:a,p:b,e:c,x:d}},
hd(a){var s,r,q,p,o,n="_$dart_js",m=a[v.dispatchPropertyName]
if(m==null)if($.i8==null){A.mP()
m=a[v.dispatchPropertyName]}if(m!=null){s=m.p
if(!1===s)return m.i
if(!0===s)return a
r=Object.getPrototypeOf(a)
if(s===r)return m.i
if(m.e===r)throw A.d(A.iZ("Return interceptor for "+A.n(s(a,m))))}q=a.constructor
if(q==null)p=null
else{o=$.fz
if(o==null)o=$.fz=A.hc(n)
p=q[o]}if(p!=null)return p
p=A.mS(a)
if(p!=null)return p
if(typeof a=="function")return B.a9
s=Object.getPrototypeOf(a)
if(s==null)return B.A
if(s===Object.prototype)return B.A
if(typeof q=="function"){o=$.fz
if(o==null)o=$.fz=A.hc(n)
Object.defineProperty(q,o,{value:B.n,enumerable:false,writable:true,configurable:true})
return B.n}return B.n},
iH(a,b){if(a<0||a>4294967295)throw A.d(A.P(a,0,4294967295,"length",null))
return J.kN(new Array(a),b)},
kN(a,b){var s=A.x(a,b.h("r<0>"))
s.$flags=1
return s},
bo(a){if(typeof a=="number"){if(Math.floor(a)==a)return J.c0.prototype
return J.d6.prototype}if(typeof a=="string")return J.aS.prototype
if(a==null)return J.c1.prototype
if(typeof a=="boolean")return J.d5.prototype
if(Array.isArray(a))return J.r.prototype
if(typeof a!="object"){if(typeof a=="function")return J.aB.prototype
if(typeof a=="symbol")return J.bw.prototype
if(typeof a=="bigint")return J.U.prototype
return a}if(a instanceof A.e)return a
return J.hd(a)},
cL(a){if(typeof a=="string")return J.aS.prototype
if(a==null)return a
if(Array.isArray(a))return J.r.prototype
if(typeof a!="object"){if(typeof a=="function")return J.aB.prototype
if(typeof a=="symbol")return J.bw.prototype
if(typeof a=="bigint")return J.U.prototype
return a}if(a instanceof A.e)return a
return J.hd(a)},
e2(a){if(a==null)return a
if(Array.isArray(a))return J.r.prototype
if(typeof a!="object"){if(typeof a=="function")return J.aB.prototype
if(typeof a=="symbol")return J.bw.prototype
if(typeof a=="bigint")return J.U.prototype
return a}if(a instanceof A.e)return a
return J.hd(a)},
mJ(a){if(typeof a=="number")return J.bv.prototype
if(typeof a=="string")return J.aS.prototype
if(a==null)return a
if(!(a instanceof A.e))return J.bg.prototype
return a},
mK(a){if(typeof a=="string")return J.aS.prototype
if(a==null)return a
if(!(a instanceof A.e))return J.bg.prototype
return a},
jG(a){if(a==null)return a
if(typeof a!="object"){if(typeof a=="function")return J.aB.prototype
if(typeof a=="symbol")return J.bw.prototype
if(typeof a=="bigint")return J.U.prototype
return a}if(a instanceof A.e)return a
return J.hd(a)},
ab(a,b){if(a==null)return b==null
if(typeof a!="object")return b!=null&&a===b
return J.bo(a).I(a,b)},
kk(a,b){return J.e2(a).t(a,b)},
kl(a){return J.jG(a).bt(a)},
ii(a,b,c){return J.jG(a).bu(a,b,c)},
km(a,b){return J.mJ(a).m(a,b)},
ij(a,b){return J.e2(a).H(a,b)},
ag(a){return J.bo(a).gu(a)},
cN(a){return J.e2(a).gG(a)},
ac(a){return J.cL(a).gk(a)},
kn(a){return J.bo(a).gF(a)},
ko(a,b,c){return J.e2(a).ak(a,b,c)},
kp(a,b){return J.e2(a).aq(a,b)},
hv(a,b,c){return J.mK(a).a1(a,b,c)},
b4(a){return J.bo(a).i(a)},
d3:function d3(){},
d5:function d5(){},
c1:function c1(){},
c2:function c2(){},
aT:function aT(){},
dl:function dl(){},
bg:function bg(){},
aB:function aB(){},
U:function U(){},
bw:function bw(){},
r:function r(a){this.$ti=a},
d4:function d4(){},
ey:function ey(a){this.$ti=a},
bR:function bR(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
bv:function bv(){},
c0:function c0(){},
d6:function d6(){},
aS:function aS(){}},A={hC:function hC(){},
iI(a){return new A.bx("Field '"+a+"' has not been initialized.")},
kQ(a){return new A.bx("Field '"+a+"' has already been initialized.")},
aX(a,b){a=a+b&536870911
a=a+((a&524287)<<10)&536870911
return a^a>>>6},
hL(a){a=a+((a&67108863)<<3)&536870911
a^=a>>>11
return a+((a&16383)<<15)&536870911},
h9(a,b,c){return a},
i9(a){var s,r
for(s=$.a9.length,r=0;r<s;++r)if(a===$.a9[r])return!0
return!1},
iX(a,b,c,d){A.bA(b,"start")
if(c!=null){A.bA(c,"end")
if(b>c)A.u(A.P(b,0,c,"start",null))}return new A.cn(a,b,c,d.h("cn<0>"))},
kU(a,b,c,d){if(t.O.b(a))return new A.bV(a,b,c.h("@<0>").E(d).h("bV<1,2>"))
return new A.bb(a,b,c.h("@<0>").E(d).h("bb<1,2>"))},
l6(a,b,c){var s="count"
if(t.O.b(a)){A.hw(b,s,t.S)
A.bA(b,s)
return new A.bW(a,b,c.h("bW<0>"))}A.hw(b,s,t.S)
A.bA(b,s)
return new A.bd(a,b,c.h("bd<0>"))},
ex(){return new A.be("No element")},
iE(){return new A.be("Too many elements")},
kL(){return new A.be("Too few elements")},
bx:function bx(a){this.a=a},
eP:function eP(){},
i:function i(){},
V:function V(){},
cn:function cn(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.$ti=d},
b9:function b9(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
bb:function bb(a,b,c){this.a=a
this.b=b
this.$ti=c},
bV:function bV(a,b,c){this.a=a
this.b=b
this.$ti=c},
c6:function c6(a,b,c){var _=this
_.a=null
_.b=a
_.c=b
_.$ti=c},
a5:function a5(a,b,c){this.a=a
this.b=b
this.$ti=c},
cp:function cp(a,b,c){this.a=a
this.b=b
this.$ti=c},
bh:function bh(a,b,c){this.a=a
this.b=b
this.$ti=c},
bd:function bd(a,b,c){this.a=a
this.b=b
this.$ti=c},
bW:function bW(a,b,c){this.a=a
this.b=b
this.$ti=c},
ch:function ch(a,b,c){this.a=a
this.b=b
this.$ti=c},
T:function T(){},
ce:function ce(a,b){this.a=a
this.$ti=b},
jU(a){var s=A.jT(a)
if(s!=null)return s
return"minified:"+a},
nP(a,b){var s
if(b!=null){s=b.x
if(s!=null)return s}return t.aU.b(a)},
n(a){var s
if(typeof a=="string")return a
if(typeof a=="number"){if(a!==0)return""+a}else if(!0===a)return"true"
else if(!1===a)return"false"
else if(a==null)return"null"
s=J.b4(a)
return s},
dm(a){var s,r=$.iR
if(r==null)r=$.iR=Symbol("identityHashCode")
s=a[r]
if(s==null){s=Math.random()*0x3fffffff|0
a[r]=s}return s},
iS(a,b){var s,r=/^\s*[+-]?((0x[a-f0-9]+)|(\d+)|([a-z0-9]+))\s*$/i.exec(a)
if(r==null)return null
if(3>=r.length)return A.b(r,3)
s=r[3]
if(s!=null)return parseInt(a,10)
if(r[2]!=null)return parseInt(a,16)
return null},
dn(a){var s,r,q,p
if(a instanceof A.e)return A.Y(A.aw(a),null)
s=J.bo(a)
if(s===B.a8||s===B.aa||t.ak.b(a)){r=B.p(a)
if(r!=="Object"&&r!=="")return r
q=a.constructor
if(typeof q=="function"){p=q.name
if(typeof p=="string"&&p!=="Object"&&p!=="")return p}}return A.Y(A.aw(a),null)},
iT(a){var s,r,q
if(a==null||typeof a=="number"||A.cI(a))return J.b4(a)
if(typeof a=="string")return JSON.stringify(a)
if(a instanceof A.aP)return a.i(0)
if(a instanceof A.aH)return a.bq(!0)
s=$.kj()
for(r=0;r<1;++r){q=s[r].du(a)
if(q!=null)return q}return"Instance of '"+A.dn(a)+"'"},
kY(a,b,c){var s,r,q,p
if(c<=500&&b===0&&c===a.length)return String.fromCharCode.apply(null,a)
for(s=b,r="";s<c;s=q){q=s+500
p=q<c?q:c
r+=String.fromCharCode.apply(null,a.subarray(s,p))}return r},
bz(a){var s
if(a<=65535)return String.fromCharCode(a)
if(a<=1114111){s=a-65536
return String.fromCharCode((B.a.B(s,10)|55296)>>>0,s&1023|56320)}throw A.d(A.P(a,0,1114111,null,null))},
kZ(a,b,c,d,e,f,g,h,i){var s,r,q,p=b-1
if(0<=a&&a<100){a+=400
p-=4800}s=B.a.n(h,1000)
r=Date.UTC(a,p,c,d,e,f,g+B.a.l(h-s,1000))
q=!0
if(!isNaN(r))if(!(r<-864e13))if(!(r>864e13))q=r===864e13&&s!==0
if(q)return null
return r},
W(a){if(a.date===void 0)a.date=new Date(a.a)
return a.date},
eO(a){return a.c?A.W(a).getUTCFullYear()+0:A.W(a).getFullYear()+0},
eM(a){return a.c?A.W(a).getUTCMonth()+1:A.W(a).getMonth()+1},
eJ(a){return a.c?A.W(a).getUTCDate()+0:A.W(a).getDate()+0},
eK(a){return a.c?A.W(a).getUTCHours()+0:A.W(a).getHours()+0},
eL(a){return a.c?A.W(a).getUTCMinutes()+0:A.W(a).getMinutes()+0},
eN(a){return a.c?A.W(a).getUTCSeconds()+0:A.W(a).getSeconds()+0},
hJ(a){return a.c?A.W(a).getUTCMilliseconds()+0:A.W(a).getMilliseconds()+0},
kX(a){return B.a.n((a.c?A.W(a).getUTCDay()+0:A.W(a).getDay()+0)+6,7)+1},
kW(a){var s=a.$thrownJsError
if(s==null)return null
return A.bp(s)},
iU(a,b){var s
if(a.$thrownJsError==null){s=new Error()
A.C(a,s)
a.$thrownJsError=s
s.stack=b.i(0)}},
he(a){throw A.d(A.i4(a))},
b(a,b){if(a==null)J.ac(a)
throw A.d(A.ha(a,b))},
ha(a,b){var s,r="index",q=null
if(!A.bJ(b))return new A.ah(!0,b,r,q)
s=J.ac(a)
if(b<0||b>=s)return A.ew(b,s,a,q,r)
return new A.aC(q,q,!0,b,r,"Value not in range")},
mG(a,b,c){if(a>c)return A.P(a,0,c,"start",null)
if(b!=null)if(b<a||b>c)return A.P(b,a,c,"end",null)
return new A.ah(!0,b,"end",null)},
i4(a){return new A.ah(!0,a,null,null)},
d(a){return A.C(a,new Error())},
C(a,b){var s
if(a==null)a=new A.aE()
b.dartException=a
s=A.n1
if("defineProperty" in Object){Object.defineProperty(b,"message",{get:s})
b.name=""}else b.toString=s
return b},
n1(){return J.b4(this.dartException)},
u(a,b){throw A.C(a,b==null?new Error():b)},
l(a,b,c){var s
if(b==null)b=0
if(c==null)c=0
s=Error()
A.u(A.lY(a,b,c),s)},
lY(a,b,c){var s,r,q,p,o,n,m,l,k
if(typeof b=="string")s=b
else{r="[]=;add;removeWhere;retainWhere;removeRange;setRange;setInt8;setInt16;setInt32;setUint8;setUint16;setUint32;setFloat32;setFloat64".split(";")
q=r.length
p=b
if(p>q){c=p/q|0
p%=q}s=r[p]}o=typeof c=="string"?c:"modify;remove from;add to".split(";")[c]
n=t.b.b(a)?"list":"ByteData"
m=a.$flags|0
l="a "
if((m&4)!==0)k="constant "
else if((m&2)!==0){k="unmodifiable "
l="an "}else k=(m&1)!==0?"fixed-length ":""
return new A.co("'"+s+"': Cannot "+o+" "+l+k+n)},
hr(a){throw A.d(A.aQ(a))},
aF(a){var s,r,q,p,o,n
a=A.jM(a.replace(String({}),"$receiver$"))
s=a.match(/\\\$[a-zA-Z]+\\\$/g)
if(s==null)s=A.x([],t.s)
r=s.indexOf("\\$arguments\\$")
q=s.indexOf("\\$argumentsExpr\\$")
p=s.indexOf("\\$expr\\$")
o=s.indexOf("\\$method\\$")
n=s.indexOf("\\$receiver\\$")
return new A.f_(a.replace(new RegExp("\\\\\\$arguments\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$argumentsExpr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$expr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$method\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$receiver\\\\\\$","g"),"((?:x|[^x])*)"),r,q,p,o,n)},
f0(a){return function($expr$){var $argumentsExpr$="$arguments$"
try{$expr$.$method$($argumentsExpr$)}catch(s){return s.message}}(a)},
iY(a){return function($expr$){try{$expr$.$method$}catch(s){return s.message}}(a)},
hD(a,b){var s=b==null,r=s?null:b.method
return new A.d8(a,r,s?null:b.receiver)},
I(a){var s
if(a==null)return new A.eF(a)
if(a instanceof A.bY){s=a.a
return A.b3(a,s==null?A.bl(s):s)}if(typeof a!=="object")return a
if("dartException" in a)return A.b3(a,a.dartException)
return A.my(a)},
b3(a,b){if(t.Q.b(b))if(b.$thrownJsError==null)b.$thrownJsError=a
return b},
my(a){var s,r,q,p,o,n,m,l,k,j,i,h,g
if(!("message" in a))return a
s=a.message
if("number" in a&&typeof a.number=="number"){r=a.number
q=r&65535
if((B.a.B(r,16)&8191)===10)switch(q){case 438:return A.b3(a,A.hD(A.n(s)+" (Error "+q+")",null))
case 445:case 5007:A.n(s)
return A.b3(a,new A.cb())}}if(a instanceof TypeError){p=$.k2()
o=$.k3()
n=$.k4()
m=$.k5()
l=$.k8()
k=$.k9()
j=$.k7()
$.k6()
i=$.kb()
h=$.ka()
g=p.N(s)
if(g!=null)return A.b3(a,A.hD(A.A(s),g))
else{g=o.N(s)
if(g!=null){g.method="call"
return A.b3(a,A.hD(A.A(s),g))}else if(n.N(s)!=null||m.N(s)!=null||l.N(s)!=null||k.N(s)!=null||j.N(s)!=null||m.N(s)!=null||i.N(s)!=null||h.N(s)!=null){A.A(s)
return A.b3(a,new A.cb())}}return A.b3(a,new A.dw(typeof s=="string"?s:""))}if(a instanceof RangeError){if(typeof s=="string"&&s.indexOf("call stack")!==-1)return new A.cl()
s=function(b){try{return String(b)}catch(f){}return null}(a)
return A.b3(a,new A.ah(!1,null,null,typeof s=="string"?s.replace(/^RangeError:\s*/,""):s))}if(typeof InternalError=="function"&&a instanceof InternalError)if(typeof s=="string"&&s==="too much recursion")return new A.cl()
return a},
bp(a){var s
if(a instanceof A.bY)return a.b
if(a==null)return new A.cA(a)
s=a.$cachedTrace
if(s!=null)return s
s=new A.cA(a)
if(typeof a==="object")a.$cachedTrace=s
return s},
jJ(a){if(a==null)return J.ag(a)
if(typeof a=="object")return A.dm(a)
return J.ag(a)},
m8(a,b,c,d,e,f){t.Z.a(a)
switch(A.c(b)){case 0:return a.$0()
case 1:return a.$1(c)
case 2:return a.$2(c,d)
case 3:return a.$3(c,d,e)
case 4:return a.$4(c,d,e,f)}throw A.d(A.iz("Unsupported number of arguments for wrapped closure"))},
bN(a,b){var s
if(a==null)return null
s=a.$identity
if(!!s)return s
s=A.mE(a,b)
a.$identity=s
return s},
mE(a,b){var s
switch(b){case 0:s=a.$0
break
case 1:s=a.$1
break
case 2:s=a.$2
break
case 3:s=a.$3
break
case 4:s=a.$4
break
default:s=null}if(s!=null)return s.bind(a)
return function(c,d,e){return function(f,g,h,i){return e(c,d,f,g,h,i)}}(a,b,A.m8)},
kw(a2){var s,r,q,p,o,n,m,l,k,j,i=a2.co,h=a2.iS,g=a2.iI,f=a2.nDA,e=a2.aI,d=a2.fs,c=a2.cs,b=d[0],a=c[0],a0=i[b],a1=a2.fT
a1.toString
s=h?Object.create(new A.dt().constructor.prototype):Object.create(new A.br(null,null).constructor.prototype)
s.$initialize=s.constructor
r=h?function static_tear_off(){this.$initialize()}:function tear_off(a3,a4){this.$initialize(a3,a4)}
s.constructor=r
r.prototype=s
s.$_name=b
s.$_target=a0
q=!h
if(q)p=A.is(b,a0,g,f)
else{s.$static_name=b
p=a0}s.$S=A.ks(a1,h,g)
s[a]=p
for(o=p,n=1;n<d.length;++n){m=d[n]
if(typeof m=="string"){l=i[m]
k=m
m=l}else k=""
j=c[n]
if(j!=null){if(q)m=A.is(k,m,g,f)
s[j]=m}if(n===e)o=m}s.$C=o
s.$R=a2.rC
s.$D=a2.dV
return r},
ks(a,b,c){if(typeof a=="number")return a
if(typeof a=="string"){if(b)throw A.d("Cannot compute signature for static tearoff.")
return function(d,e){return function(){return e(this,d)}}(a,A.kq)}throw A.d("Error in functionType of tearoff")},
kt(a,b,c,d){var s=A.iq
switch(b?-1:a){case 0:return function(e,f){return function(){return f(this)[e]()}}(c,s)
case 1:return function(e,f){return function(g){return f(this)[e](g)}}(c,s)
case 2:return function(e,f){return function(g,h){return f(this)[e](g,h)}}(c,s)
case 3:return function(e,f){return function(g,h,i){return f(this)[e](g,h,i)}}(c,s)
case 4:return function(e,f){return function(g,h,i,j){return f(this)[e](g,h,i,j)}}(c,s)
case 5:return function(e,f){return function(g,h,i,j,k){return f(this)[e](g,h,i,j,k)}}(c,s)
default:return function(e,f){return function(){return e.apply(f(this),arguments)}}(d,s)}},
is(a,b,c,d){if(c)return A.kv(a,b,d)
return A.kt(b.length,d,a,b)},
ku(a,b,c,d){var s=A.iq,r=A.kr
switch(b?-1:a){case 0:throw A.d(new A.dr("Intercepted function with no arguments."))
case 1:return function(e,f,g){return function(){return f(this)[e](g(this))}}(c,r,s)
case 2:return function(e,f,g){return function(h){return f(this)[e](g(this),h)}}(c,r,s)
case 3:return function(e,f,g){return function(h,i){return f(this)[e](g(this),h,i)}}(c,r,s)
case 4:return function(e,f,g){return function(h,i,j){return f(this)[e](g(this),h,i,j)}}(c,r,s)
case 5:return function(e,f,g){return function(h,i,j,k){return f(this)[e](g(this),h,i,j,k)}}(c,r,s)
case 6:return function(e,f,g){return function(h,i,j,k,l){return f(this)[e](g(this),h,i,j,k,l)}}(c,r,s)
default:return function(e,f,g){return function(){var q=[g(this)]
Array.prototype.push.apply(q,arguments)
return e.apply(f(this),q)}}(d,r,s)}},
kv(a,b,c){var s,r
if($.io==null)$.io=A.im("interceptor")
if($.ip==null)$.ip=A.im("receiver")
s=b.length
r=A.ku(s,c,a,b)
return r},
i5(a){return A.kw(a)},
kq(a,b){return A.cE(v.typeUniverse,A.aw(a.a),b)},
iq(a){return a.a},
kr(a){return a.b},
im(a){var s,r,q,p=new A.br("receiver","interceptor"),o=Object.getOwnPropertyNames(p)
o.$flags=1
s=o
for(o=s.length,r=0;r<o;++r){q=s[r]
if(p[q]===a)return q}throw A.d(A.J("Field name "+a+" not found.",null))},
hc(a){return v.getIsolateTag(a)},
n7(a,b){var s=$.w
if(s===B.d)return a
return s.cD(a,b)},
nO(a,b,c){Object.defineProperty(a,b,{value:c,enumerable:false,writable:true,configurable:true})},
mS(a){var s,r,q,p,o,n=A.A($.jH.$1(a)),m=$.hb[n]
if(m!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}s=$.hi[n]
if(s!=null)return s
r=v.interceptorsByTag[n]
if(r==null){q=A.jp($.jD.$2(a,n))
if(q!=null){m=$.hb[q]
if(m!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}s=$.hi[q]
if(s!=null)return s
r=v.interceptorsByTag[q]
n=q}}if(r==null)return null
s=r.prototype
p=n[0]
if(p==="!"){m=A.hj(s)
$.hb[n]=m
Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}if(p==="~"){$.hi[n]=s
return s}if(p==="-"){o=A.hj(s)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:o,enumerable:false,writable:true,configurable:true})
return o.i}if(p==="+")return A.jK(a,s)
if(p==="*")throw A.d(A.iZ(n))
if(v.leafTags[n]===true){o=A.hj(s)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:o,enumerable:false,writable:true,configurable:true})
return o.i}else return A.jK(a,s)},
jK(a,b){var s=Object.getPrototypeOf(a)
Object.defineProperty(s,v.dispatchPropertyName,{value:J.ia(b,s,null,null),enumerable:false,writable:true,configurable:true})
return b},
hj(a){return J.ia(a,!1,null,!!a.$ia4)},
mU(a,b,c){var s=b.prototype
if(v.leafTags[a]===true)return A.hj(s)
else return J.ia(s,c,null,null)},
mP(){if(!0===$.i8)return
$.i8=!0
A.mQ()},
mQ(){var s,r,q,p,o,n,m,l
$.hb=Object.create(null)
$.hi=Object.create(null)
A.mO()
s=v.interceptorsByTag
r=Object.getOwnPropertyNames(s)
if(typeof window!="undefined"){window
q=function(){}
for(p=0;p<r.length;++p){o=r[p]
n=$.jL.$1(o)
if(n!=null){m=A.mU(o,s[o],n)
if(m!=null){Object.defineProperty(n,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
q.prototype=n}}}}for(p=0;p<r.length;++p){o=r[p]
if(/^[A-Za-z_]/.test(o)){l=s[o]
s["!"+o]=l
s["~"+o]=l
s["-"+o]=l
s["+"+o]=l
s["*"+o]=l}}},
mO(){var s,r,q,p,o,n,m=B.D()
m=A.bM(B.E,A.bM(B.F,A.bM(B.q,A.bM(B.q,A.bM(B.G,A.bM(B.H,A.bM(B.I(B.p),m)))))))
if(typeof dartNativeDispatchHooksTransformer!="undefined"){s=dartNativeDispatchHooksTransformer
if(typeof s=="function")s=[s]
if(Array.isArray(s))for(r=0;r<s.length;++r){q=s[r]
if(typeof q=="function")m=q(m)||m}}p=m.getTag
o=m.getUnknownTag
n=m.prototypeForTag
$.jH=new A.hf(p)
$.jD=new A.hg(o)
$.jL=new A.hh(n)},
bM(a,b){return a(b)||b},
mF(a,b){var s=b.length,r=v.rttc[""+s+";"+a]
if(r==null)return null
if(s===0)return r
if(s===r.length)return r.apply(null,b)
return r(b)},
kP(a,b,c,d,e,f){var s=b?"m":"",r=c?"":"i",q=d?"u":"",p=e?"s":"",o=function(g,h){try{return new RegExp(g,h)}catch(n){return n}}(a,s+r+q+p+f)
if(o instanceof RegExp)return o
throw A.d(A.ev("Illegal RegExp pattern ("+String(o)+")",a,null))},
mH(a){if(a.indexOf("$",0)>=0)return a.replace(/\$/g,"$$$$")
return a},
jM(a){if(/[[\]{}()*+?.\\^$|]/.test(a))return a.replace(/[[\]{}()*+?.\\^$|]/g,"\\$&")
return a},
mZ(a,b,c){var s=A.n_(a,b,c)
return s},
n_(a,b,c){var s,r,q
if(b===""){if(a==="")return c
s=a.length
for(r=c,q=0;q<s;++q)r=r+a[q]+c
return r.charCodeAt(0)==0?r:r}if(a.indexOf(b,0)<0)return a
if(a.length<500||c.indexOf("$",0)>=0)return a.split(b).join(c)
return a.replace(new RegExp(A.jM(b),"g"),A.mH(c))},
cy:function cy(a,b){this.a=a
this.b=b},
bF:function bF(a,b){this.a=a
this.b=b},
cz:function cz(a,b){this.a=a
this.b=b},
bT:function bT(){},
bU:function bU(a,b,c){this.a=a
this.b=b
this.$ti=c},
cf:function cf(){},
f_:function f_(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
cb:function cb(){},
d8:function d8(a,b,c){this.a=a
this.b=b
this.c=c},
dw:function dw(a){this.a=a},
eF:function eF(a){this.a=a},
bY:function bY(a,b){this.a=a
this.b=b},
cA:function cA(a){this.a=a
this.b=null},
aP:function aP(){},
cS:function cS(){},
cT:function cT(){},
du:function du(){},
dt:function dt(){},
br:function br(a,b){this.a=a
this.b=b},
dr:function dr(a){this.a=a},
c3:function c3(a){var _=this
_.a=0
_.f=_.e=_.d=_.c=_.b=null
_.r=0
_.$ti=a},
ez:function ez(a,b){var _=this
_.a=a
_.b=b
_.d=_.c=null},
c5:function c5(a,b){this.a=a
this.$ti=b},
c4:function c4(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=null
_.$ti=d},
eA:function eA(a,b){this.a=a
this.$ti=b},
b8:function b8(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=null
_.$ti=d},
hf:function hf(a){this.a=a},
hg:function hg(a){this.a=a},
hh:function hh(a){this.a=a},
aH:function aH(){},
b0:function b0(){},
d7:function d7(a,b){var _=this
_.a=a
_.b=b
_.e=_.d=_.c=null},
fA:function fA(a){this.b=a},
n0(a){throw A.C(new A.bx("Field '"+a+"' has been assigned during initialization."),new Error())},
D(){throw A.C(A.iI(""),new Error())},
jS(){throw A.C(A.kQ(""),new Error())},
fl(a){var s=new A.fk(a)
return s.b=s},
fk:function fk(a){this.a=a
this.b=null},
lW(a){return a},
cH(a,b,c){},
lZ(a){return a},
iO(a,b,c){var s
A.cH(a,b,c)
s=new DataView(a,b)
return s},
ak(a,b,c){A.cH(a,b,c)
c=B.a.l(a.byteLength-b,4)
return new Int32Array(a,b,c)},
kV(a,b,c){A.cH(a,b,c)
return new Uint32Array(a,b,c)},
iP(a){return new Uint8Array(a)},
ar(a,b,c){A.cH(a,b,c)
return c==null?new Uint8Array(a,b):new Uint8Array(a,b,c)},
aL(a,b,c){if(a>>>0!==a||a>=c)throw A.d(A.ha(b,a))},
lX(a,b,c){var s
if(!(a>>>0!==a))s=b>>>0!==b||a>b||b>c
else s=!0
if(s)throw A.d(A.mG(a,b,c))
return b},
aU:function aU(){},
by:function by(){},
c9:function c9(){},
fJ:function fJ(a){this.a=a},
c7:function c7(){},
L:function L(){},
c8:function c8(){},
a6:function a6(){},
dc:function dc(){},
dd:function dd(){},
de:function de(){},
df:function df(){},
dg:function dg(){},
dh:function dh(){},
di:function di(){},
ca:function ca(){},
bc:function bc(){},
cu:function cu(){},
cv:function cv(){},
cw:function cw(){},
cx:function cx(){},
hK(a,b){var s=b.c
return s==null?b.c=A.cC(a,"ai",[b.x]):s},
iV(a){var s=a.w
if(s===6||s===7)return A.iV(a.x)
return s===11||s===12},
l5(a){return a.as},
b2(a){return A.fI(v.typeUniverse,a,!1)},
bm(a1,a2,a3,a4){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0=a2.w
switch(a0){case 5:case 1:case 2:case 3:case 4:return a2
case 6:s=a2.x
r=A.bm(a1,s,a3,a4)
if(r===s)return a2
return A.jf(a1,r,!0)
case 7:s=a2.x
r=A.bm(a1,s,a3,a4)
if(r===s)return a2
return A.je(a1,r,!0)
case 8:q=a2.y
p=A.bL(a1,q,a3,a4)
if(p===q)return a2
return A.cC(a1,a2.x,p)
case 9:o=a2.x
n=A.bm(a1,o,a3,a4)
m=a2.y
l=A.bL(a1,m,a3,a4)
if(n===o&&l===m)return a2
return A.hW(a1,n,l)
case 10:k=a2.x
j=a2.y
i=A.bL(a1,j,a3,a4)
if(i===j)return a2
return A.jg(a1,k,i)
case 11:h=a2.x
g=A.bm(a1,h,a3,a4)
f=a2.y
e=A.mv(a1,f,a3,a4)
if(g===h&&e===f)return a2
return A.jd(a1,g,e)
case 12:d=a2.y
a4+=d.length
c=A.bL(a1,d,a3,a4)
o=a2.x
n=A.bm(a1,o,a3,a4)
if(c===d&&n===o)return a2
return A.hX(a1,n,c,!0)
case 13:b=a2.x
if(b<a4)return a2
a=a3[b-a4]
if(a==null)return a2
return a
default:throw A.d(A.cP("Attempted to substitute unexpected RTI kind "+a0))}},
bL(a,b,c,d){var s,r,q,p,o=b.length,n=A.fN(o)
for(s=!1,r=0;r<o;++r){q=b[r]
p=A.bm(a,q,c,d)
if(p!==q)s=!0
n[r]=p}return s?n:b},
mw(a,b,c,d){var s,r,q,p,o,n,m=b.length,l=A.fN(m)
for(s=!1,r=0;r<m;r+=3){q=b[r]
p=b[r+1]
o=b[r+2]
n=A.bm(a,o,c,d)
if(n!==o)s=!0
l.splice(r,3,q,p,n)}return s?l:b},
mv(a,b,c,d){var s,r=b.a,q=A.bL(a,r,c,d),p=b.b,o=A.bL(a,p,c,d),n=b.c,m=A.mw(a,n,c,d)
if(q===r&&o===p&&m===n)return b
s=new A.dN()
s.a=q
s.b=o
s.c=m
return s},
x(a,b){a[v.arrayRti]=b
return a},
jF(a){var s=a.$S
if(s!=null){if(typeof s=="number")return A.mN(s)
return a.$S()}return null},
mR(a,b){var s
if(A.iV(b))if(a instanceof A.aP){s=A.jF(a)
if(s!=null)return s}return A.aw(a)},
aw(a){if(a instanceof A.e)return A.S(a)
if(Array.isArray(a))return A.am(a)
return A.i1(J.bo(a))},
am(a){var s=a[v.arrayRti],r=t.gn
if(s==null)return r
if(s.constructor!==r.constructor)return r
return s},
S(a){var s=a.$ti
return s!=null?s:A.i1(a)},
i1(a){var s=a.constructor,r=s.$ccache
if(r!=null)return r
return A.m5(a,s)},
m5(a,b){var s=a instanceof A.aP?Object.getPrototypeOf(Object.getPrototypeOf(a)).constructor:b,r=A.lH(v.typeUniverse,s.name)
b.$ccache=r
return r},
mN(a){var s,r=v.types,q=r[a]
if(typeof q=="string"){s=A.fI(v.typeUniverse,q,!1)
r[a]=s
return s}return q},
mM(a){return A.bn(A.S(a))},
i3(a){var s
if(a instanceof A.aH)return A.mI(a.$r,a.bg())
s=a instanceof A.aP?A.jF(a):null
if(s!=null)return s
if(t.dm.b(a))return J.kn(a).a
if(Array.isArray(a))return A.am(a)
return A.aw(a)},
bn(a){var s=a.r
return s==null?a.r=new A.fH(a):s},
mI(a,b){var s,r,q=b,p=q.length
if(p===0)return t.bQ
if(0>=p)return A.b(q,0)
s=A.cE(v.typeUniverse,A.i3(q[0]),"@<0>")
for(r=1;r<p;++r){if(!(r<q.length))return A.b(q,r)
s=A.ji(v.typeUniverse,s,A.i3(q[r]))}return A.cE(v.typeUniverse,s,a)},
an(a){return A.bn(A.fI(v.typeUniverse,a,!1))},
m4(a){var s=this
s.b=A.mt(s)
return s.b(a)},
mt(a){var s,r,q,p,o
if(a===t.K)return A.me
if(A.bq(a))return A.mi
s=a.w
if(s===6)return A.m2
if(s===1)return A.jx
if(s===7)return A.m9
r=A.ms(a)
if(r!=null)return r
if(s===8){q=a.x
if(a.y.every(A.bq)){a.f="$i"+q
if(q==="j")return A.mc
if(a===t.m)return A.mb
return A.mh}}else if(s===10){p=A.mF(a.x,a.y)
o=p==null?A.jx:p
return o==null?A.bl(o):o}return A.m0},
ms(a){if(a.w===8){if(a===t.S)return A.bJ
if(a===t.i||a===t.o)return A.md
if(a===t.N)return A.mg
if(a===t.v)return A.cI}return null},
m3(a){var s=this,r=A.m_
if(A.bq(s))r=A.lP
else if(s===t.K)r=A.bl
else if(A.bO(s)){r=A.m1
if(s===t.h6)r=A.lO
else if(s===t.dk)r=A.jp
else if(s===t.fQ)r=A.lM
else if(s===t.cg)r=A.jo
else if(s===t.cD)r=A.lN
else if(s===t.an)r=A.jm}else if(s===t.S)r=A.c
else if(s===t.N)r=A.A
else if(s===t.v)r=A.e0
else if(s===t.o)r=A.jn
else if(s===t.i)r=A.Q
else if(s===t.m)r=A.B
s.a=r
return s.a(a)},
m0(a){var s=this
if(a==null)return A.bO(s)
return A.jI(v.typeUniverse,A.mR(a,s),s)},
m2(a){if(a==null)return!0
return this.x.b(a)},
mh(a){var s,r=this
if(a==null)return A.bO(r)
s=r.f
if(a instanceof A.e)return!!a[s]
return!!J.bo(a)[s]},
mc(a){var s,r=this
if(a==null)return A.bO(r)
if(typeof a!="object")return!1
if(Array.isArray(a))return!0
s=r.f
if(a instanceof A.e)return!!a[s]
return!!J.bo(a)[s]},
mb(a){var s=this
if(a==null)return!1
if(typeof a=="object"){if(a instanceof A.e)return!!a[s.f]
return!0}if(typeof a=="function")return!0
return!1},
jw(a){if(typeof a=="object"){if(a instanceof A.e)return t.m.b(a)
return!0}if(typeof a=="function")return!0
return!1},
m_(a){var s=this
if(a==null){if(A.bO(s))return a}else if(s.b(a))return a
throw A.C(A.jr(a,s),new Error())},
m1(a){var s=this
if(a==null||s.b(a))return a
throw A.C(A.jr(a,s),new Error())},
jr(a,b){return new A.bG("TypeError: "+A.j9(a,A.Y(b,null)))},
mC(a,b,c,d){if(A.jI(v.typeUniverse,a,b))return a
throw A.C(A.lz("The type argument '"+A.Y(a,null)+"' is not a subtype of the type variable bound '"+A.Y(b,null)+"' of type variable '"+c+"' in '"+d+"'."),new Error())},
j9(a,b){return A.bX(a)+": type '"+A.Y(A.i3(a),null)+"' is not a subtype of type '"+b+"'"},
lz(a){return new A.bG("TypeError: "+a)},
ae(a,b){return new A.bG("TypeError: "+A.j9(a,b))},
m9(a){var s=this
return s.x.b(a)||A.hK(v.typeUniverse,s).b(a)},
me(a){return a!=null},
bl(a){if(a!=null)return a
throw A.C(A.ae(a,"Object"),new Error())},
mi(a){return!0},
lP(a){return a},
jx(a){return!1},
cI(a){return!0===a||!1===a},
e0(a){if(!0===a)return!0
if(!1===a)return!1
throw A.C(A.ae(a,"bool"),new Error())},
lM(a){if(!0===a)return!0
if(!1===a)return!1
if(a==null)return a
throw A.C(A.ae(a,"bool?"),new Error())},
Q(a){if(typeof a=="number")return a
throw A.C(A.ae(a,"double"),new Error())},
lN(a){if(typeof a=="number")return a
if(a==null)return a
throw A.C(A.ae(a,"double?"),new Error())},
bJ(a){return typeof a=="number"&&Math.floor(a)===a},
c(a){if(typeof a=="number"&&Math.floor(a)===a)return a
throw A.C(A.ae(a,"int"),new Error())},
lO(a){if(typeof a=="number"&&Math.floor(a)===a)return a
if(a==null)return a
throw A.C(A.ae(a,"int?"),new Error())},
md(a){return typeof a=="number"},
jn(a){if(typeof a=="number")return a
throw A.C(A.ae(a,"num"),new Error())},
jo(a){if(typeof a=="number")return a
if(a==null)return a
throw A.C(A.ae(a,"num?"),new Error())},
mg(a){return typeof a=="string"},
A(a){if(typeof a=="string")return a
throw A.C(A.ae(a,"String"),new Error())},
jp(a){if(typeof a=="string")return a
if(a==null)return a
throw A.C(A.ae(a,"String?"),new Error())},
B(a){if(A.jw(a))return a
throw A.C(A.ae(a,"JSObject"),new Error())},
jm(a){if(a==null)return a
if(A.jw(a))return a
throw A.C(A.ae(a,"JSObject?"),new Error())},
jA(a,b){var s,r,q
for(s="",r="",q=0;q<a.length;++q,r=", ")s+=r+A.Y(a[q],b)
return s},
mm(a,b){var s,r,q,p,o,n,m=a.x,l=a.y
if(""===m)return"("+A.jA(l,b)+")"
s=l.length
r=m.split(",")
q=r.length-s
for(p="(",o="",n=0;n<s;++n,o=", "){p+=o
if(q===0)p+="{"
p+=A.Y(l[n],b)
if(q>=0)p+=" "+r[q];++q}return p+"})"},
jt(a3,a4,a5){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1=", ",a2=null
if(a5!=null){s=a5.length
if(a4==null)a4=A.x([],t.s)
else a2=a4.length
r=a4.length
for(q=s;q>0;--q)B.b.t(a4,"T"+(r+q))
for(p=t.X,o="<",n="",q=0;q<s;++q,n=a1){m=a4.length
l=m-1-q
if(!(l>=0))return A.b(a4,l)
o=o+n+a4[l]
k=a5[q]
j=k.w
if(!(j===2||j===3||j===4||j===5||k===p))o+=" extends "+A.Y(k,a4)}o+=">"}else o=""
p=a3.x
i=a3.y
h=i.a
g=h.length
f=i.b
e=f.length
d=i.c
c=d.length
b=A.Y(p,a4)
for(a="",a0="",q=0;q<g;++q,a0=a1)a+=a0+A.Y(h[q],a4)
if(e>0){a+=a0+"["
for(a0="",q=0;q<e;++q,a0=a1)a+=a0+A.Y(f[q],a4)
a+="]"}if(c>0){a+=a0+"{"
for(a0="",q=0;q<c;q+=3,a0=a1){a+=a0
if(d[q+1])a+="required "
a+=A.Y(d[q+2],a4)+" "+d[q]}a+="}"}if(a2!=null){a4.toString
a4.length=a2}return o+"("+a+") => "+b},
Y(a,b){var s,r,q,p,o,n,m,l=a.w
if(l===5)return"erased"
if(l===2)return"dynamic"
if(l===3)return"void"
if(l===1)return"Never"
if(l===4)return"any"
if(l===6){s=a.x
r=A.Y(s,b)
q=s.w
return(q===11||q===12?"("+r+")":r)+"?"}if(l===7)return"FutureOr<"+A.Y(a.x,b)+">"
if(l===8){p=A.mx(a.x)
o=a.y
return o.length>0?p+("<"+A.jA(o,b)+">"):p}if(l===10)return A.mm(a,b)
if(l===11)return A.jt(a,b,null)
if(l===12)return A.jt(a.x,b,a.y)
if(l===13){n=a.x
m=b.length
n=m-1-n
if(!(n>=0&&n<m))return A.b(b,n)
return b[n]}return"?"},
mx(a){var s=A.jT(a)
if(s!=null)return s
return"minified:"+a},
lI(a,b){var s=a.tR[b]
while(typeof s=="string")s=a.tR[s]
return s},
lH(a,b){var s,r,q,p,o,n=a.eT,m=n[b]
if(m==null)return A.fI(a,b,!1)
else if(typeof m=="number"){s=m
r=A.cD(a,5,"#")
q=A.fN(s)
for(p=0;p<s;++p)q[p]=r
o=A.cC(a,b,q)
n[b]=o
return o}else return m},
lG(a,b){return A.jk(a.tR,b)},
lF(a,b){return A.jk(a.eT,b)},
fI(a,b,c){var s,r=a.eC,q=r.get(b)
if(q!=null)return q
s=A.jh(a,null,b,!1)
r.set(b,s)
return s},
cE(a,b,c){var s,r,q=b.z
if(q==null)q=b.z=new Map()
s=q.get(c)
if(s!=null)return s
r=A.jh(a,b,c,!0)
q.set(c,r)
return r},
ji(a,b,c){var s,r,q,p=b.Q
if(p==null)p=b.Q=new Map()
s=c.as
r=p.get(s)
if(r!=null)return r
q=A.hW(a,b,c.w===9?c.y:[c])
p.set(s,q)
return q},
jh(a,b,c,d){return A.lw(A.lq(a,b,c,d))},
b1(a,b){b.a=A.m3
b.b=A.m4
return b},
cD(a,b,c){var s,r,q=a.eC.get(c)
if(q!=null)return q
s=new A.al(null,null)
s.w=b
s.as=c
r=A.b1(a,s)
a.eC.set(c,r)
return r},
jf(a,b,c){var s,r=b.as+"?",q=a.eC.get(r)
if(q!=null)return q
s=A.lD(a,b,r,c)
a.eC.set(r,s)
return s},
lD(a,b,c,d){var s,r,q
if(d){s=b.w
r=!0
if(!A.bq(b))if(!(b===t.P||b===t.T))if(s!==6)r=s===7&&A.bO(b.x)
if(r)return b
else if(s===1)return t.P}q=new A.al(null,null)
q.w=6
q.x=b
q.as=c
return A.b1(a,q)},
je(a,b,c){var s,r=b.as+"/",q=a.eC.get(r)
if(q!=null)return q
s=A.lB(a,b,r,c)
a.eC.set(r,s)
return s},
lB(a,b,c,d){var s,r
if(d){s=b.w
if(A.bq(b)||b===t.K)return b
else if(s===1)return A.cC(a,"ai",[b])
else if(b===t.P||b===t.T)return t.eH}r=new A.al(null,null)
r.w=7
r.x=b
r.as=c
return A.b1(a,r)},
lE(a,b){var s,r,q=""+b+"^",p=a.eC.get(q)
if(p!=null)return p
s=new A.al(null,null)
s.w=13
s.x=b
s.as=q
r=A.b1(a,s)
a.eC.set(q,r)
return r},
cB(a){var s,r,q,p=a.length
for(s="",r="",q=0;q<p;++q,r=",")s+=r+a[q].as
return s},
lA(a){var s,r,q,p,o,n=a.length
for(s="",r="",q=0;q<n;q+=3,r=","){p=a[q]
o=a[q+1]?"!":":"
s+=r+p+o+a[q+2].as}return s},
cC(a,b,c){var s,r,q,p=b
if(c.length>0)p+="<"+A.cB(c)+">"
s=a.eC.get(p)
if(s!=null)return s
r=new A.al(null,null)
r.w=8
r.x=b
r.y=c
if(c.length>0)r.c=c[0]
r.as=p
q=A.b1(a,r)
a.eC.set(p,q)
return q},
hW(a,b,c){var s,r,q,p,o,n
if(b.w===9){s=b.x
r=b.y.concat(c)}else{r=c
s=b}q=s.as+(";<"+A.cB(r)+">")
p=a.eC.get(q)
if(p!=null)return p
o=new A.al(null,null)
o.w=9
o.x=s
o.y=r
o.as=q
n=A.b1(a,o)
a.eC.set(q,n)
return n},
jg(a,b,c){var s,r,q="+"+(b+"("+A.cB(c)+")"),p=a.eC.get(q)
if(p!=null)return p
s=new A.al(null,null)
s.w=10
s.x=b
s.y=c
s.as=q
r=A.b1(a,s)
a.eC.set(q,r)
return r},
jd(a,b,c){var s,r,q,p,o,n=b.as,m=c.a,l=m.length,k=c.b,j=k.length,i=c.c,h=i.length,g="("+A.cB(m)
if(j>0){s=l>0?",":""
g+=s+"["+A.cB(k)+"]"}if(h>0){s=l>0?",":""
g+=s+"{"+A.lA(i)+"}"}r=n+(g+")")
q=a.eC.get(r)
if(q!=null)return q
p=new A.al(null,null)
p.w=11
p.x=b
p.y=c
p.as=r
o=A.b1(a,p)
a.eC.set(r,o)
return o},
hX(a,b,c,d){var s,r=b.as+("<"+A.cB(c)+">"),q=a.eC.get(r)
if(q!=null)return q
s=A.lC(a,b,c,r,d)
a.eC.set(r,s)
return s},
lC(a,b,c,d,e){var s,r,q,p,o,n,m,l
if(e){s=c.length
r=A.fN(s)
for(q=0,p=0;p<s;++p){o=c[p]
if(o.w===1){r[p]=o;++q}}if(q>0){n=A.bm(a,b,r,0)
m=A.bL(a,c,r,0)
return A.hX(a,n,m,c!==m)}}l=new A.al(null,null)
l.w=12
l.x=b
l.y=c
l.as=d
return A.b1(a,l)},
lq(a,b,c,d){return{u:a,e:b,r:c,s:[],p:0,n:d}},
lw(a){var s,r,q,p,o,n,m,l=a.r,k=a.s
for(s=l.length,r=0;r<s;){q=l.charCodeAt(r)
if(q>=48&&q<=57)r=A.ls(r+1,q,l,k)
else if((((q|32)>>>0)-97&65535)<26||q===95||q===36||q===124)r=A.jb(a,r,l,k,!1)
else if(q===46)r=A.jb(a,r,l,k,!0)
else{++r
switch(q){case 44:break
case 58:k.push(!1)
break
case 33:k.push(!0)
break
case 59:k.push(A.bk(a.u,a.e,k.pop()))
break
case 94:k.push(A.lE(a.u,k.pop()))
break
case 35:k.push(A.cD(a.u,5,"#"))
break
case 64:k.push(A.cD(a.u,2,"@"))
break
case 126:k.push(A.cD(a.u,3,"~"))
break
case 60:k.push(a.p)
a.p=k.length
break
case 62:A.lu(a,k)
break
case 38:A.lt(a,k)
break
case 63:p=a.u
k.push(A.jf(p,A.bk(p,a.e,k.pop()),a.n))
break
case 47:p=a.u
k.push(A.je(p,A.bk(p,a.e,k.pop()),a.n))
break
case 40:k.push(-3)
k.push(a.p)
a.p=k.length
break
case 41:A.lr(a,k)
break
case 91:k.push(a.p)
a.p=k.length
break
case 93:o=k.splice(a.p)
A.jc(a.u,a.e,o)
a.p=k.pop()
k.push(o)
k.push(-1)
break
case 123:k.push(a.p)
a.p=k.length
break
case 125:o=k.splice(a.p)
A.lx(a.u,a.e,o)
a.p=k.pop()
k.push(o)
k.push(-2)
break
case 43:n=l.indexOf("(",r)
k.push(l.substring(r,n))
k.push(-4)
k.push(a.p)
a.p=k.length
r=n+1
break
default:throw"Bad character "+q}}}m=k.pop()
return A.bk(a.u,a.e,m)},
ls(a,b,c,d){var s,r,q=b-48
for(s=c.length;a<s;++a){r=c.charCodeAt(a)
if(!(r>=48&&r<=57))break
q=q*10+(r-48)}d.push(q)
return a},
jb(a,b,c,d,e){var s,r,q,p,o,n,m=b+1
for(s=c.length;m<s;++m){r=c.charCodeAt(m)
if(r===46){if(e)break
e=!0}else{if(!((((r|32)>>>0)-97&65535)<26||r===95||r===36||r===124))q=r>=48&&r<=57
else q=!0
if(!q)break}}p=c.substring(b,m)
if(e){s=a.u
o=a.e
if(o.w===9)o=o.x
n=A.lI(s,o.x)[p]
if(n==null)A.u('No "'+p+'" in "'+A.l5(o)+'"')
d.push(A.cE(s,o,n))}else d.push(p)
return m},
lu(a,b){var s,r=a.u,q=A.ja(a,b),p=b.pop()
if(typeof p=="string")b.push(A.cC(r,p,q))
else{s=A.bk(r,a.e,p)
switch(s.w){case 11:b.push(A.hX(r,s,q,a.n))
break
default:b.push(A.hW(r,s,q))
break}}},
lr(a,b){var s,r,q,p=a.u,o=b.pop(),n=null,m=null
if(typeof o=="number")switch(o){case-1:n=b.pop()
break
case-2:m=b.pop()
break
default:b.push(o)
break}else b.push(o)
s=A.ja(a,b)
o=b.pop()
switch(o){case-3:o=b.pop()
if(n==null)n=p.sEA
if(m==null)m=p.sEA
r=A.bk(p,a.e,o)
q=new A.dN()
q.a=s
q.b=n
q.c=m
b.push(A.jd(p,r,q))
return
case-4:b.push(A.jg(p,b.pop(),s))
return
default:throw A.d(A.cP("Unexpected state under `()`: "+A.n(o)))}},
lt(a,b){var s=b.pop()
if(0===s){b.push(A.cD(a.u,1,"0&"))
return}if(1===s){b.push(A.cD(a.u,4,"1&"))
return}throw A.d(A.cP("Unexpected extended operation "+A.n(s)))},
ja(a,b){var s=b.splice(a.p)
A.jc(a.u,a.e,s)
a.p=b.pop()
return s},
bk(a,b,c){if(typeof c=="string")return A.cC(a,c,a.sEA)
else if(typeof c=="number"){b.toString
return A.lv(a,b,c)}else return c},
jc(a,b,c){var s,r=c.length
for(s=0;s<r;++s)c[s]=A.bk(a,b,c[s])},
lx(a,b,c){var s,r=c.length
for(s=2;s<r;s+=3)c[s]=A.bk(a,b,c[s])},
lv(a,b,c){var s,r,q=b.w
if(q===9){if(c===0)return b.x
s=b.y
r=s.length
if(c<=r)return s[c-1]
c-=r
b=b.x
q=b.w}else if(c===0)return b
if(q!==8)throw A.d(A.cP("Indexed base must be an interface type"))
s=b.y
if(c<=s.length)return s[c-1]
throw A.d(A.cP("Bad index "+c+" for "+b.i(0)))},
jI(a,b,c){var s,r=b.d
if(r==null)r=b.d=new Map()
s=r.get(c)
if(s==null){s=A.G(a,b,null,c,null)
r.set(c,s)}return s},
G(a,b,c,d,e){var s,r,q,p,o,n,m,l,k,j,i
if(b===d)return!0
if(A.bq(d))return!0
s=b.w
if(s===4)return!0
if(A.bq(b))return!1
if(b.w===1)return!0
r=s===13
if(r)if(A.G(a,c[b.x],c,d,e))return!0
q=d.w
p=t.P
if(b===p||b===t.T){if(q===7)return A.G(a,b,c,d.x,e)
return d===p||d===t.T||q===6}if(d===t.K){if(s===7)return A.G(a,b.x,c,d,e)
return s!==6}if(s===7){if(!A.G(a,b.x,c,d,e))return!1
return A.G(a,A.hK(a,b),c,d,e)}if(s===6)return A.G(a,p,c,d,e)&&A.G(a,b.x,c,d,e)
if(q===7){if(A.G(a,b,c,d.x,e))return!0
return A.G(a,b,c,A.hK(a,d),e)}if(q===6)return A.G(a,b,c,p,e)||A.G(a,b,c,d.x,e)
if(r)return!1
p=s!==11
if((!p||s===12)&&d===t.Z)return!0
o=s===10
if(o&&d===t.gT)return!0
if(q===12){if(b===t.g)return!0
if(s!==12)return!1
n=b.y
m=d.y
l=n.length
if(l!==m.length)return!1
c=c==null?n:n.concat(c)
e=e==null?m:m.concat(e)
for(k=0;k<l;++k){j=n[k]
i=m[k]
if(!A.G(a,j,c,i,e)||!A.G(a,i,e,j,c))return!1}return A.jv(a,b.x,c,d.x,e)}if(q===11){if(b===t.g)return!0
if(p)return!1
return A.jv(a,b,c,d,e)}if(s===8){if(q!==8)return!1
return A.ma(a,b,c,d,e)}if(o&&q===10)return A.mf(a,b,c,d,e)
return!1},
jv(a3,a4,a5,a6,a7){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2
if(!A.G(a3,a4.x,a5,a6.x,a7))return!1
s=a4.y
r=a6.y
q=s.a
p=r.a
o=q.length
n=p.length
if(o>n)return!1
m=n-o
l=s.b
k=r.b
j=l.length
i=k.length
if(o+j<n+i)return!1
for(h=0;h<o;++h){g=q[h]
if(!A.G(a3,p[h],a7,g,a5))return!1}for(h=0;h<m;++h){g=l[h]
if(!A.G(a3,p[o+h],a7,g,a5))return!1}for(h=0;h<i;++h){g=l[m+h]
if(!A.G(a3,k[h],a7,g,a5))return!1}f=s.c
e=r.c
d=f.length
c=e.length
for(b=0,a=0;a<c;a+=3){a0=e[a]
for(;;){if(b>=d)return!1
a1=f[b]
b+=3
if(a0<a1)return!1
a2=f[b-2]
if(a1<a0){if(a2)return!1
continue}g=e[a+1]
if(a2&&!g)return!1
g=f[b-1]
if(!A.G(a3,e[a+2],a7,g,a5))return!1
break}}while(b<d){if(f[b+1])return!1
b+=3}return!0},
ma(a,b,c,d,e){var s,r,q,p,o,n=b.x,m=d.x
while(n!==m){s=a.tR[n]
if(s==null)return!1
if(typeof s=="string"){n=s
continue}r=s[m]
if(r==null)return!1
q=r.length
p=q>0?new Array(q):v.typeUniverse.sEA
for(o=0;o<q;++o)p[o]=A.cE(a,b,r[o])
return A.jl(a,p,null,c,d.y,e)}return A.jl(a,b.y,null,c,d.y,e)},
jl(a,b,c,d,e,f){var s,r=b.length
for(s=0;s<r;++s)if(!A.G(a,b[s],d,e[s],f))return!1
return!0},
mf(a,b,c,d,e){var s,r=b.y,q=d.y,p=r.length
if(p!==q.length)return!1
if(b.x!==d.x)return!1
for(s=0;s<p;++s)if(!A.G(a,r[s],c,q[s],e))return!1
return!0},
bO(a){var s=a.w,r=!0
if(!(a===t.P||a===t.T))if(!A.bq(a))if(s!==6)r=s===7&&A.bO(a.x)
return r},
bq(a){var s=a.w
return s===2||s===3||s===4||s===5||a===t.X},
jk(a,b){var s,r,q=Object.keys(b),p=q.length
for(s=0;s<p;++s){r=q[s]
a[r]=b[r]}},
fN(a){return a>0?new Array(a):v.typeUniverse.sEA},
al:function al(a,b){var _=this
_.a=a
_.b=b
_.r=_.f=_.d=_.c=null
_.w=0
_.as=_.Q=_.z=_.y=_.x=null},
dN:function dN(){this.c=this.b=this.a=null},
fH:function fH(a){this.a=a},
dM:function dM(){},
bG:function bG(a){this.a=a},
lf(){var s,r,q
if(self.scheduleImmediate!=null)return A.mz()
if(self.MutationObserver!=null&&self.document!=null){s={}
r=self.document.createElement("div")
q=self.document.createElement("span")
s.a=null
new self.MutationObserver(A.bN(new A.fe(s),1)).observe(r,{childList:true})
return new A.fd(s,r,q)}else if(self.setImmediate!=null)return A.mA()
return A.mB()},
lg(a){self.scheduleImmediate(A.bN(new A.ff(t.M.a(a)),0))},
lh(a){self.setImmediate(A.bN(new A.fg(t.M.a(a)),0))},
li(a){t.M.a(a)
A.ly(0,a)},
ly(a,b){var s=new A.fF()
s.cb(a,b)
return s},
aM(a){return new A.dF(new A.F($.w,a.h("F<0>")),a.h("dF<0>"))},
aK(a,b){a.$2(0,null)
b.b=!0
return b.a},
R(a,b){A.lQ(a,b)},
aJ(a,b){b.aQ(a)},
aI(a,b){b.aR(A.I(a),A.bp(a))},
lQ(a,b){var s,r,q=new A.fP(b),p=new A.fQ(b)
if(a instanceof A.F)a.bp(q,p,t.z)
else{s=t.z
if(a instanceof A.F)a.b0(q,p,s)
else{r=new A.F($.w,t.d)
r.a=8
r.c=a
r.bp(q,p,s)}}},
aN(a){var s=function(b,c){return function(d,e){while(true){try{b(d,e)
break}catch(r){e=r
d=c}}}}(a,1)
return $.w.bM(new A.h7(s),t.H,t.S,t.z)},
hx(a){var s
if(t.Q.b(a)){s=a.ga0()
if(s!=null)return s}return B.k},
m6(a,b){if($.w===B.d)return null
return null},
m7(a,b){if($.w!==B.d)A.m6(a,b)
if(b==null)if(t.Q.b(a)){b=a.ga0()
if(b==null){A.iU(a,B.k)
b=B.k}}else b=B.k
else if(t.Q.b(a))A.iU(a,b)
return new A.ad(a,b)},
hV(a,b,c){var s,r,q,p,o={},n=o.a=a
for(s=t.d;r=n.a,(r&4)!==0;n=a){a=s.a(n.c)
o.a=a}if(n===b){s=A.l8()
b.aw(new A.ad(new A.ah(!0,n,null,"Cannot complete a future with itself"),s))
return}q=b.a&1
s=n.a=r|q
if((s&24)===0){p=t.F.a(b.c)
b.a=b.a&1|4
b.c=n
n.bh(p)
return}if(!c)if(b.c==null)n=(s&16)===0||q!==0
else n=!1
else n=!0
if(n){p=b.ag()
b.af(o.a)
A.bE(b,p)
return}b.a^=2
A.e1(null,null,b.b,t.M.a(new A.fs(o,b)))},
bE(a,b){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d={},c=d.a=a
for(s=t.n,r=t.F;;){q={}
p=c.a
o=(p&16)===0
n=!o
if(b==null){if(n&&(p&1)===0){m=s.a(c.c)
A.h5(m.a,m.b)}return}q.a=b
l=b.a
for(c=b;l!=null;c=l,l=k){c.a=null
A.bE(d.a,c)
q.a=l
k=l.a}p=d.a
j=p.c
q.b=n
q.c=j
if(o){i=c.c
i=(i&1)!==0||(i&15)===8}else i=!0
if(i){h=c.b.b
if(n){p=p.b===h
p=!(p||p)}else p=!1
if(p){s.a(j)
A.h5(j.a,j.b)
return}g=$.w
if(g!==h)$.w=h
else g=null
c=c.c
if((c&15)===8)new A.fw(q,d,n).$0()
else if(o){if((c&1)!==0)new A.fv(q,j).$0()}else if((c&2)!==0)new A.fu(d,q).$0()
if(g!=null)$.w=g
c=q.c
if(c instanceof A.F){p=q.a.$ti
p=p.h("ai<2>").b(c)||!p.y[1].b(c)}else p=!1
if(p){f=q.a.b
if((c.a&24)!==0){e=r.a(f.c)
f.c=null
b=f.ah(e)
f.a=c.a&30|f.a&1
f.c=c.c
d.a=c
continue}else A.hV(c,f,!0)
return}}f=q.a.b
e=r.a(f.c)
f.c=null
b=f.ah(e)
c=q.b
p=q.c
if(!c){f.$ti.c.a(p)
f.a=8
f.c=p}else{s.a(p)
f.a=f.a&1|16
f.c=p}d.a=f
c=f}},
mo(a,b){var s
if(t.R.b(a))return b.bM(a,t.z,t.K,t.l)
s=t.x
if(s.b(a))return s.a(a)
throw A.d(A.ax(a,"onError",u.c))},
mk(){var s,r
for(s=$.bK;s!=null;s=$.bK){$.cK=null
r=s.b
$.bK=r
if(r==null)$.cJ=null
s.a.$0()}},
mu(){$.i2=!0
try{A.mk()}finally{$.cK=null
$.i2=!1
if($.bK!=null)$.id().$1(A.jE())}},
jB(a){var s=new A.dG(a),r=$.cJ
if(r==null){$.bK=$.cJ=s
if(!$.i2)$.id().$1(A.jE())}else $.cJ=r.b=s},
mr(a){var s,r,q,p=$.bK
if(p==null){A.jB(a)
$.cK=$.cJ
return}s=new A.dG(a)
r=$.cK
if(r==null){s.b=p
$.bK=$.cK=s}else{q=r.b
s.b=q
$.cK=r.b=s
if(q==null)$.cJ=s}},
nn(a,b){A.h9(a,"stream",t.K)
return new A.dZ(b.h("dZ<0>"))},
h5(a,b){A.mr(new A.h6(a,b))},
jy(a,b,c,d,e){var s,r=$.w
if(r===c)return d.$0()
$.w=c
s=r
try{r=d.$0()
return r}finally{$.w=s}},
jz(a,b,c,d,e,f,g){var s,r=$.w
if(r===c)return d.$1(e)
$.w=c
s=r
try{r=d.$1(e)
return r}finally{$.w=s}},
mq(a,b,c,d,e,f,g,h,i){var s,r=$.w
if(r===c)return d.$2(e,f)
$.w=c
s=r
try{r=d.$2(e,f)
return r}finally{$.w=s}},
e1(a,b,c,d){t.M.a(d)
if(B.d!==c){d=c.cC(d)
d=d}A.jB(d)},
fe:function fe(a){this.a=a},
fd:function fd(a,b,c){this.a=a
this.b=b
this.c=c},
ff:function ff(a){this.a=a},
fg:function fg(a){this.a=a},
fF:function fF(){},
fG:function fG(a,b){this.a=a
this.b=b},
dF:function dF(a,b){this.a=a
this.b=!1
this.$ti=b},
fP:function fP(a){this.a=a},
fQ:function fQ(a){this.a=a},
h7:function h7(a){this.a=a},
ad:function ad(a,b){this.a=a
this.b=b},
dI:function dI(){},
cq:function cq(a,b){this.a=a
this.$ti=b},
bj:function bj(a,b,c,d,e){var _=this
_.a=null
_.b=a
_.c=b
_.d=c
_.e=d
_.$ti=e},
F:function F(a,b){var _=this
_.a=0
_.b=a
_.c=null
_.$ti=b},
fp:function fp(a,b){this.a=a
this.b=b},
ft:function ft(a,b){this.a=a
this.b=b},
fs:function fs(a,b){this.a=a
this.b=b},
fr:function fr(a,b){this.a=a
this.b=b},
fq:function fq(a,b){this.a=a
this.b=b},
fw:function fw(a,b,c){this.a=a
this.b=b
this.c=c},
fx:function fx(a,b){this.a=a
this.b=b},
fy:function fy(a){this.a=a},
fv:function fv(a,b){this.a=a
this.b=b},
fu:function fu(a,b){this.a=a
this.b=b},
dG:function dG(a){this.a=a
this.b=null},
dZ:function dZ(a){this.$ti=a},
cG:function cG(){},
dV:function dV(){},
fD:function fD(a,b){this.a=a
this.b=b},
fE:function fE(a,b,c){this.a=a
this.b=b
this.c=c},
h6:function h6(a,b){this.a=a
this.b=b},
d9(a,b){return new A.c3(a.h("@<0>").E(b).h("c3<1,2>"))},
hI(a){var s,r
if(A.i9(a))return"{...}"
s=new A.cm("")
try{r={}
B.b.t($.a9,a)
s.a+="{"
r.a=!0
a.aU(0,new A.eD(r,s))
s.a+="}"}finally{if(0>=$.a9.length)return A.b($.a9,-1)
$.a9.pop()}r=s.a
return r.charCodeAt(0)==0?r:r},
k:function k(){},
a_:function a_(){},
eD:function eD(a,b){this.a=a
this.b=b},
lK(a,b,c){var s,r,q,p,o,n=c-b
if(n<=4096)s=$.kh()
else s=new Uint8Array(n)
for(r=a.length,q=0;q<n;++q){p=b+q
if(!(p>=0&&p<r))return A.b(a,p)
o=a[p]
if((o&255)!==o)o=255
s[q]=o}return s},
lJ(a,b,c,d){var s=a?$.kg():$.kf()
if(s==null)return null
if(0===c&&d===b.length)return A.jj(s,b)
return A.jj(s,b.subarray(c,d))},
jj(a,b){var s,r
try{s=a.decode(b)
return s}catch(r){}return null},
lL(a){switch(a){case 65:return"Missing extension byte"
case 67:return"Unexpected extension byte"
case 69:return"Invalid UTF-8 byte"
case 71:return"Overlong encoding"
case 73:return"Out of unicode range"
case 75:return"Encoded surrogate"
case 77:return"Unfinished UTF-8 octet sequence"
default:return""}},
fL:function fL(){},
fK:function fK(){},
bS:function bS(){},
cW:function cW(){},
d_:function d_(){},
dy:function dy(){},
f2:function f2(){},
fM:function fM(a){this.b=0
this.c=a},
cF:function cF(a){this.a=a
this.b=16
this.c=0},
hU(a,b){var s=A.lp(a,b)
if(s==null)throw A.d(A.ev("Could not parse BigInt",a,null))
return s},
lm(a,b){var s,r,q=$.E(),p=a.length,o=4-p%4
if(o===4)o=0
for(s=0,r=0;r<p;++r){s=s*10+a.charCodeAt(r)-48;++o
if(o===4){q=q.q(0,$.ie()).S(0,A.cr(s))
s=0
o=0}}if(b)return q.D(0)
return q},
j1(a){if(48<=a&&a<=57)return a-48
return(a|32)-97+10},
ln(a,b,c){var s,r,q,p,o,n,m,l=a.length,k=l-b,j=B.l.cE(k/4),i=new Uint16Array(j),h=j-1,g=k-h*4
for(s=b,r=0,q=0;q<g;++q,s=p){p=s+1
if(!(s<l))return A.b(a,s)
o=A.j1(a.charCodeAt(s))
if(o>=16)return null
r=r*16+o}n=h-1
if(!(h>=0&&h<j))return A.b(i,h)
i[h]=r
for(;s<l;n=m){for(r=0,q=0;q<4;++q,s=p){p=s+1
if(!(s>=0&&s<l))return A.b(a,s)
o=A.j1(a.charCodeAt(s))
if(o>=16)return null
r=r*16+o}m=n-1
if(!(n>=0&&n<j))return A.b(i,n)
i[n]=r}if(j===1){if(0>=j)return A.b(i,0)
l=i[0]===0}else l=!1
if(l)return $.E()
l=A.a1(j,i)
return new A.z(l===0?!1:c,i,l)},
lp(a,b){var s,r,q,p,o,n
if(a==="")return null
s=$.kd().a3(a)
if(s==null)return null
r=s.b
q=r.length
if(1>=q)return A.b(r,1)
p=r[1]==="-"
if(4>=q)return A.b(r,4)
o=r[4]
n=r[3]
if(5>=q)return A.b(r,5)
if(o!=null)return A.lm(o,p)
if(n!=null)return A.ln(n,2,p)
return null},
a1(a,b){var s,r=b.length
for(;;){if(a>0){s=a-1
if(!(s<r))return A.b(b,s)
s=b[s]===0}else s=!1
if(!s)break;--a}return a},
hS(a,b,c,d){var s,r,q,p=new Uint16Array(d),o=c-b
for(s=a.length,r=0;r<o;++r){q=b+r
if(!(q>=0&&q<s))return A.b(a,q)
q=a[q]
if(!(r<d))return A.b(p,r)
p[r]=q}return p},
O(a){var s
if(a===0)return $.E()
if(a===1)return $.Z()
if(a===2)return $.ih()
if(Math.abs(a)<4294967296)return A.cr(B.l.bP(a))
s=A.lj(a)
return s},
cr(a){var s,r,q,p,o=a<0
if(o){if(a===-9223372036854776e3){s=new Uint16Array(4)
s[3]=32768
r=A.a1(4,s)
return new A.z(r!==0,s,r)}a=-a}if(a<65536){s=new Uint16Array(1)
s[0]=a
r=A.a1(1,s)
return new A.z(r===0?!1:o,s,r)}if(a<=4294967295){s=new Uint16Array(2)
s[0]=a&65535
s[1]=B.a.B(a,16)
r=A.a1(2,s)
return new A.z(r===0?!1:o,s,r)}r=B.a.l(B.a.gbw(a)-1,16)+1
s=new Uint16Array(r)
for(q=0;a!==0;q=p){p=q+1
if(!(q<r))return A.b(s,q)
s[q]=a&65535
a=B.a.l(a,65536)}r=A.a1(r,s)
return new A.z(r===0?!1:o,s,r)},
lj(a){var s,r,q,p,o,n,m,l
if(isNaN(a)||a==1/0||a==-1/0)throw A.d(A.J("Value must be finite: "+A.n(a),null))
s=a<0
if(s)a=-a
a=Math.floor(a)
if(a===0)return $.E()
r=$.kc()
for(q=r.$flags|0,p=0;p<8;++p){q&2&&A.l(r)
if(!(p<8))return A.b(r,p)
r[p]=0}q=J.kl(B.e.gaP(r))
q.$flags&2&&A.l(q,13)
q.setFloat64(0,a,!0)
o=(r[7]<<4>>>0)+(r[6]>>>4)-1075
n=new Uint16Array(4)
n[0]=(r[1]<<8>>>0)+r[0]
n[1]=(r[3]<<8>>>0)+r[2]
n[2]=(r[5]<<8>>>0)+r[4]
n[3]=r[6]&15|16
m=new A.z(!1,n,4)
if(o<0)l=m.Z(0,-o)
else l=o>0?m.O(0,o):m
if(s)return l.D(0)
return l},
hT(a,b,c,d){var s,r,q,p,o
if(b===0)return 0
if(c===0&&d===a)return b
for(s=b-1,r=a.length,q=d.$flags|0;s>=0;--s){p=s+c
if(!(s<r))return A.b(a,s)
o=a[s]
q&2&&A.l(d)
if(!(p>=0&&p<d.length))return A.b(d,p)
d[p]=o}for(s=c-1;s>=0;--s){q&2&&A.l(d)
if(!(s<d.length))return A.b(d,s)
d[s]=0}return b+c},
j7(a,b,c,d){var s,r,q,p,o,n,m,l=B.a.l(c,16),k=B.a.n(c,16),j=16-k,i=B.a.O(1,j)-1
for(s=b-1,r=a.length,q=d.$flags|0,p=0;s>=0;--s){if(!(s<r))return A.b(a,s)
o=a[s]
n=s+l+1
m=B.a.Z(o,j)
q&2&&A.l(d)
if(!(n>=0&&n<d.length))return A.b(d,n)
d[n]=(m|p)>>>0
p=B.a.O((o&i)>>>0,k)}q&2&&A.l(d)
if(!(l>=0&&l<d.length))return A.b(d,l)
d[l]=p},
j2(a,b,c,d){var s,r,q,p=B.a.l(c,16)
if(B.a.n(c,16)===0)return A.hT(a,b,p,d)
s=b+p+1
A.j7(a,b,c,d)
for(r=d.$flags|0,q=p;--q,q>=0;){r&2&&A.l(d)
if(!(q<d.length))return A.b(d,q)
d[q]=0}r=s-1
if(!(r>=0&&r<d.length))return A.b(d,r)
if(d[r]===0)s=r
return s},
lo(a,b,c,d){var s,r,q,p,o,n,m=B.a.l(c,16),l=B.a.n(c,16),k=16-l,j=B.a.O(1,l)-1,i=a.length
if(!(m>=0&&m<i))return A.b(a,m)
s=B.a.Z(a[m],l)
r=b-m-1
for(q=d.$flags|0,p=0;p<r;++p){o=p+m+1
if(!(o<i))return A.b(a,o)
n=a[o]
o=B.a.O((n&j)>>>0,k)
q&2&&A.l(d)
if(!(p<d.length))return A.b(d,p)
d[p]=(o|s)>>>0
s=B.a.Z(n,l)}q&2&&A.l(d)
if(!(r>=0&&r<d.length))return A.b(d,r)
d[r]=s},
fh(a,b,c,d){var s,r,q,p,o=b-d
if(o===0)for(s=b-1,r=a.length,q=c.length;s>=0;--s){if(!(s<r))return A.b(a,s)
p=a[s]
if(!(s<q))return A.b(c,s)
o=p-c[s]
if(o!==0)return o}return o},
lk(a,b,c,d,e){var s,r,q,p,o,n
for(s=a.length,r=c.length,q=e.$flags|0,p=0,o=0;o<d;++o){if(!(o<s))return A.b(a,o)
n=a[o]
if(!(o<r))return A.b(c,o)
p+=n+c[o]
q&2&&A.l(e)
if(!(o<e.length))return A.b(e,o)
e[o]=p&65535
p=B.a.B(p,16)}for(o=d;o<b;++o){if(!(o>=0&&o<s))return A.b(a,o)
p+=a[o]
q&2&&A.l(e)
if(!(o<e.length))return A.b(e,o)
e[o]=p&65535
p=B.a.B(p,16)}q&2&&A.l(e)
if(!(b>=0&&b<e.length))return A.b(e,b)
e[b]=p},
dH(a,b,c,d,e){var s,r,q,p,o,n
for(s=a.length,r=c.length,q=e.$flags|0,p=0,o=0;o<d;++o){if(!(o<s))return A.b(a,o)
n=a[o]
if(!(o<r))return A.b(c,o)
p+=n-c[o]
q&2&&A.l(e)
if(!(o<e.length))return A.b(e,o)
e[o]=p&65535
p=0-(B.a.B(p,16)&1)}for(o=d;o<b;++o){if(!(o>=0&&o<s))return A.b(a,o)
p+=a[o]
q&2&&A.l(e)
if(!(o<e.length))return A.b(e,o)
e[o]=p&65535
p=0-(B.a.B(p,16)&1)}},
j8(a,b,c,d,e,f){var s,r,q,p,o,n,m,l,k
if(a===0)return
for(s=b.length,r=d.length,q=d.$flags|0,p=0;--f,f>=0;e=l,c=o){o=c+1
if(!(c<s))return A.b(b,c)
n=b[c]
if(!(e>=0&&e<r))return A.b(d,e)
m=a*n+d[e]+p
l=e+1
q&2&&A.l(d)
d[e]=m&65535
p=B.a.l(m,65536)}for(;p!==0;e=l){if(!(e>=0&&e<r))return A.b(d,e)
k=d[e]+p
l=e+1
q&2&&A.l(d)
d[e]=k&65535
p=B.a.l(k,65536)}},
ll(a,b,c){var s,r,q,p=b.length
if(!(c>=0&&c<p))return A.b(b,c)
s=b[c]
if(s===a)return 65535
r=c-1
if(!(r>=0&&r<p))return A.b(b,r)
q=B.a.ad((s<<16|b[r])>>>0,a)
if(q>65535)return 65535
return q},
fo(a,b){var s=$.ke()
s=s==null?null:new s(A.bN(A.n7(a,b),1))
return new A.ct(s,b.h("ct<0>"))},
aa(a){var s=A.iS(a,null)
if(s!=null)return s
throw A.d(A.ev(a,null,null))},
kC(a,b){a=A.C(a,new Error())
if(a==null)a=A.bl(a)
a.stack=b.i(0)
throw a},
iJ(a,b,c,d){var s,r=J.iH(a,d)
if(a!==0&&b!=null)for(s=0;s<a;++s)r[s]=b
return r},
hE(a,b,c){var s,r,q=A.x([],c.h("r<0>"))
for(s=a.length,r=0;r<a.length;a.length===s||(0,A.hr)(a),++r)B.b.t(q,c.a(a[r]))
q.$flags=1
return q},
da(a,b){var s,r=A.x([],b.h("r<0>"))
for(s=J.cN(a);s.p();)B.b.t(r,s.gv())
return r},
db(a,b){var s=A.hE(a,!1,b)
s.$flags=3
return s},
la(a,b,c){var s,r
A.bA(b,"start")
s=c-b
if(s<0)throw A.d(A.P(c,b,null,"end",null))
if(s===0)return""
r=A.lb(a,b,c)
return r},
lb(a,b,c){var s=a.length
if(b>=s)return""
return A.kY(a,b,c==null||c>s?s:c)},
cd(a,b){return new A.d7(a,A.kP(a,!1,b,!1,!1,""))},
iW(a,b,c){var s=J.cN(b)
if(!s.p())return a
if(c.length===0){do a+=A.n(s.gv())
while(s.p())}else{a+=A.n(s.gv())
while(s.p())a=a+c+A.n(s.gv())}return a},
l8(){return A.bp(new Error())},
it(a,b,c,d,e,f,g,h){var s=A.kZ(a,b,c,d,e,f,g,h,!0)
if(s==null)s=new A.eu(a,b,c,d,e,f,g,h).$0()
return new A.a3(s,B.a.n(h,1000),!0)},
kA(a){var s=Math.abs(a),r=a<0?"-":""
if(s>=1000)return""+a
if(s>=100)return r+"0"+s
if(s>=10)return r+"00"+s
return r+"000"+s},
iu(a){if(a>=100)return""+a
if(a>=10)return"0"+a
return"00"+a},
cZ(a){if(a>=10)return""+a
return"0"+a},
iy(a){return new A.aR(a)},
bX(a){if(typeof a=="number"||A.cI(a)||a==null)return J.b4(a)
if(typeof a=="string")return JSON.stringify(a)
return A.iT(a)},
kD(a,b){A.h9(a,"error",t.K)
A.h9(b,"stackTrace",t.l)
A.kC(a,b)},
cP(a){return new A.cO(a)},
J(a,b){return new A.ah(!1,null,b,a)},
ax(a,b,c){return new A.ah(!0,a,b,c)},
hw(a,b,c){return a},
aV(a){var s=null
return new A.aC(s,s,!1,s,s,a)},
P(a,b,c,d,e){return new A.aC(b,c,!0,a,d,"Invalid value")},
dp(a,b,c){if(0>a||a>c)throw A.d(A.P(a,0,c,"start",null))
if(b!=null){if(a>b||b>c)throw A.d(A.P(b,a,c,"end",null))
return b}return c},
bA(a,b){if(a<0)throw A.d(A.P(a,0,null,b,null))
return a},
iD(a,b){var s=b.b
return new A.bZ(s,!0,a,null,"Index out of range")},
ew(a,b,c,d,e){return new A.bZ(b,!0,a,e,"Index out of range")},
aY(a){return new A.co(a)},
iZ(a){return new A.dv(a)},
at(a){return new A.be(a)},
aQ(a){return new A.cV(a)},
iz(a){return new A.fn(a)},
ev(a,b,c){return new A.v(a,b,c)},
kM(a,b,c){var s,r
if(A.i9(a)){if(b==="("&&c===")")return"(...)"
return b+"..."+c}s=A.x([],t.s)
B.b.t($.a9,a)
try{A.mj(a,s)}finally{if(0>=$.a9.length)return A.b($.a9,-1)
$.a9.pop()}r=A.iW(b,t.hf.a(s),", ")+c
return r.charCodeAt(0)==0?r:r},
iF(a,b,c){var s,r
if(A.i9(a))return b+"..."+c
s=new A.cm(b)
B.b.t($.a9,a)
try{r=s
r.a=A.iW(r.a,a,", ")}finally{if(0>=$.a9.length)return A.b($.a9,-1)
$.a9.pop()}s.a+=c
r=s.a
return r.charCodeAt(0)==0?r:r},
mj(a,b){var s,r,q,p,o,n,m,l=a.gG(a),k=0,j=0
for(;;){if(!(k<80||j<3))break
if(!l.p())return
s=A.n(l.gv())
B.b.t(b,s)
k+=s.length+2;++j}if(!l.p()){if(j<=5)return
if(0>=b.length)return A.b(b,-1)
r=b.pop()
if(0>=b.length)return A.b(b,-1)
q=b.pop()}else{p=l.gv();++j
if(!l.p()){if(j<=4){B.b.t(b,A.n(p))
return}r=A.n(p)
if(0>=b.length)return A.b(b,-1)
q=b.pop()
k+=r.length+2}else{o=l.gv();++j
for(;l.p();p=o,o=n){n=l.gv();++j
if(j>100){for(;;){if(!(k>75&&j>3))break
if(0>=b.length)return A.b(b,-1)
k-=b.pop().length+2;--j}B.b.t(b,"...")
return}}q=A.n(p)
r=A.n(o)
k+=r.length+q.length+4}}if(j>b.length+2){k+=5
m="..."}else m=null
for(;;){if(!(k>80&&b.length>3))break
if(0>=b.length)return A.b(b,-1)
k-=b.pop().length+2
if(m==null){k+=5
m="..."}}if(m!=null)B.b.t(b,m)
B.b.t(b,q)
B.b.t(b,r)},
eG(a,b,c,d){var s
if(B.f===c){s=J.ag(a)
b=J.ag(b)
return A.hL(A.aX(A.aX($.hu(),s),b))}if(B.f===d){s=J.ag(a)
b=J.ag(b)
c=J.ag(c)
return A.hL(A.aX(A.aX(A.aX($.hu(),s),b),c))}s=J.ag(a)
b=J.ag(b)
c=J.ag(c)
d=J.ag(d)
d=A.hL(A.aX(A.aX(A.aX(A.aX($.hu(),s),b),c),d))
return d},
z:function z(a,b,c){this.a=a
this.b=b
this.c=c},
fi:function fi(){},
fj:function fj(){},
ct:function ct(a,b){this.a=a
this.$ti=b},
eu:function eu(a,b,c,d,e,f,g,h){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.w=h},
a3:function a3(a,b,c){this.a=a
this.b=b
this.c=c},
aR:function aR(a){this.a=a},
fm:function fm(){},
q:function q(){},
cO:function cO(a){this.a=a},
aE:function aE(){},
ah:function ah(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
aC:function aC(a,b,c,d,e,f){var _=this
_.e=a
_.f=b
_.a=c
_.b=d
_.c=e
_.d=f},
bZ:function bZ(a,b,c,d,e){var _=this
_.f=a
_.a=b
_.b=c
_.c=d
_.d=e},
co:function co(a){this.a=a},
dv:function dv(a){this.a=a},
be:function be(a){this.a=a},
cV:function cV(a){this.a=a},
dk:function dk(){},
cl:function cl(){},
fn:function fn(a){this.a=a},
v:function v(a,b,c){this.a=a
this.b=b
this.c=c},
d2:function d2(){},
f:function f(){},
M:function M(){},
e:function e(){},
e_:function e_(){},
cm:function cm(a){this.a=a},
d0:function d0(a,b){this.a=a
this.$ti=b},
iG(a,b){var s,r,q,p,o
if(b.length===0)return!1
s=b.split(".")
r=v.G
for(q=s.length,p=0;p<q;++p,r=o){o=r[s[p]]
A.jm(o)
if(o==null)return!1}return a instanceof t.g.a(r)},
eE:function eE(a){this.a=a},
bH(a){var s
if(typeof a=="function")throw A.d(A.J("Attempting to rewrap a JS function.",null))
s=function(b,c){return function(d){return b(c,d,arguments.length)}}(A.lR,a)
s[$.bQ()]=a
return s},
af(a){var s
if(typeof a=="function")throw A.d(A.J("Attempting to rewrap a JS function.",null))
s=function(b,c){return function(d,e){return b(c,d,e,arguments.length)}}(A.lS,a)
s[$.bQ()]=a
return s},
fT(a){var s
if(typeof a=="function")throw A.d(A.J("Attempting to rewrap a JS function.",null))
s=function(b,c){return function(d,e,f){return b(c,d,e,f,arguments.length)}}(A.lT,a)
s[$.bQ()]=a
return s},
bI(a){var s
if(typeof a=="function")throw A.d(A.J("Attempting to rewrap a JS function.",null))
s=function(b,c){return function(d,e,f,g){return b(c,d,e,f,g,arguments.length)}}(A.lU,a)
s[$.bQ()]=a
return s},
i0(a){var s
if(typeof a=="function")throw A.d(A.J("Attempting to rewrap a JS function.",null))
s=function(b,c){return function(d,e,f,g,h){return b(c,d,e,f,g,h,arguments.length)}}(A.lV,a)
s[$.bQ()]=a
return s},
lR(a,b,c){t.Z.a(a)
if(A.c(c)>=1)return a.$1(b)
return a.$0()},
lS(a,b,c,d){t.Z.a(a)
A.c(d)
if(d>=2)return a.$2(b,c)
if(d===1)return a.$1(b)
return a.$0()},
lT(a,b,c,d,e){t.Z.a(a)
A.c(e)
if(e>=3)return a.$3(b,c,d)
if(e===2)return a.$2(b,c)
if(e===1)return a.$1(b)
return a.$0()},
lU(a,b,c,d,e,f){t.Z.a(a)
A.c(f)
if(f>=4)return a.$4(b,c,d,e)
if(f===3)return a.$3(b,c,d)
if(f===2)return a.$2(b,c)
if(f===1)return a.$1(b)
return a.$0()},
lV(a,b,c,d,e,f,g){t.Z.a(a)
A.c(g)
if(g>=5)return a.$5(b,c,d,e,f)
if(g===4)return a.$4(b,c,d,e)
if(g===3)return a.$3(b,c,d)
if(g===2)return a.$2(b,c)
if(g===1)return a.$1(b)
return a.$0()},
mL(a,b,c){return c.a(a[b])},
h8(a,b,c,d){return d.a(a[b].apply(a,c))},
bP(a,b){var s=new A.F($.w,b.h("F<0>")),r=new A.cq(s,b.h("cq<0>"))
a.then(A.bN(new A.hl(r,b),1),A.bN(new A.hm(r),1))
return s},
hl:function hl(a,b){this.a=a
this.b=b},
hm:function hm(a){this.a=a},
dQ:function dQ(a){this.a=a},
dj:function dj(){},
dx:function dx(){},
eV:function eV(a,b){this.a=a
this.b=b},
cj:function cj(a,b,c){this.a=a
this.b=b
this.c=c},
mX(){var s={},r=v.G,q=new A.F($.w,t.cd)
q.av(null)
s.a=q
r.onmessage=A.bH(new A.ho(s,new A.fO(),r))},
ho:function ho(a,b,c){this.a=a
this.b=b
this.c=c},
hn:function hn(a,b,c){this.a=a
this.b=b
this.c=c},
fO:function fO(){var _=this
_.e=_.d=_.c=_.b=_.a=null},
mD(a,b,c,d){var s,r,q,p,o,n
A.mn(a)
A.mp(a)
a.a9("PRAGMA foreign_keys = ON")
s=a.ap("PRAGMA foreign_keys")
if(!J.ab(B.b.ga_(s.ga_(s).b),1))throw A.d(B.an)
a.a9("PRAGMA busy_timeout = "+B.a.l(b.a,1000))
s=a.ap("PRAGMA journal_mode = "+d)
r=B.b.ga_(s.ga_(s).b)
s=J.ab(r,d)
if(!s)throw A.d(A.iQ("DRIVER.JOURNAL","Requested "+d+", received "+A.n(r)+".",null))
a.a9("PRAGMA synchronous = FULL")
for(s=a.ap("PRAGMA compile_options").d,q=t.X,p=-1;++p,p<s.length;){o=A.hE(s[p],!1,q)
o.$flags=3
n=A.A(B.b.ga_(o))
if(B.c.c7(n,"MAX_VARIABLE_NUMBER="))return A.aa(B.b.gda(n.split("=")))}return 999},
eZ:function eZ(a,b){var _=this
_.a=a
_.b=b
_.c=0
_.d=!1},
dJ:function dJ(a,b,c){var _=this
_.a=a
_.b=b
_.c=!1
_.d=c},
mn(a){var s,r,q
a.by(B.j,!0,B.K,"orm_decimal_avg_v1",t.gB)
a.aT(B.C,!0,new A.fU(),"orm_decimal_div_v1")
a.aT(B.j,!0,new A.fV(),"orm_decimal_round_v1")
a.a7(B.j,!0,!1,new A.fW(),"orm_decimal_cast_v1")
a.a7(B.j,!0,!1,new A.fX(),"orm_decimal_fits_v1")
a.bz(new A.fY(),"orm_decimal_v1")
for(s=["add","sub","mul"],r=0;r<3;++r){q=s[r]
a.aT(B.B,!0,new A.fZ(q),"orm_decimal_"+q+"_v1")}a.by(B.o,!0,B.L,"orm_decimal_sum_v1",t.aW)},
jN(a){var s,r,q,p=[]
for(s=a.length,r=0;r<s;++r){q=a[r]
p.push(q instanceof A.ci?new A.dR(q.a):q)}return p},
mp(a){var s,r,q,p,o=new A.h4()
for(s=[!1,!0],r=0;r<2;++r){q=s[r]
p=q?"orm_temporal_fits_v1":"orm_temporal_cast_v1"
a.a7(B.j,!0,!1,new A.h_(o,q),p)}a.a7(B.o,!0,!1,new A.h0(),"orm_instant_v1")
s=new A.h2(a)
s.$1$2("date",A.n3(),t.A)
s.$1$2("time",A.n4(),t.t)
s.$1$2("local_datetime",A.n2(),t.B)
s.$1$2("instant",new A.h1(),t.k)},
fU:function fU(){},
fV:function fV(){},
fW:function fW(){},
fX:function fX(){},
fY:function fY(){},
fZ:function fZ(a){this.a=a},
bi:function bi(a){this.a=a
this.c=this.b=0},
dL:function dL(){},
bD:function bD(a){this.a=a
this.c=this.b=null},
dK:function dK(){},
dR:function dR(a){this.a=a},
h4:function h4(){},
h_:function h_(a,b){this.a=a
this.b=b},
h0:function h0(){},
h2:function h2(a){this.a=a},
h3:function h3(a){this.a=a},
h1:function h1(){},
jQ(a,b){var s
A.e0(b)
A:{if(a==null){s=null
break A}if(A.cI(a)){s=a
break A}s=!1
if(A.bJ(a))if(b)s=a<-9007199254740991||a>9007199254740991
if(s)A.u(B.ai)
if(a instanceof A.ci){s=A.x(["real",a.a],t.f)
break A}if(typeof a=="number"){s=a
break A}if(typeof a=="string"){s=a
break A}if(t.I.b(a)){s=a
break A}if(a instanceof A.z){s=A.x(["bigint",a.i(0)],t.s)
break A}s=A.u(B.ak)}return s},
mY(a){var s
if(a==null)return null
if(typeof a==="string")return A.A(a)
if(typeof a==="boolean")return A.e0(a)
if(typeof a==="number"){A.Q(a)
s=!1
if(isFinite(a))if(Math.abs(a)<=9007199254740991)s=a===(a<0?Math.ceil(a):Math.floor(a))
return s?B.l.bP(a):a}s=A.iG(a,"Uint8Array")
if(s)return t.bm.a(a)
s=A.iG(a,"Array")
if(s){t.c.a(a)
if(A.c(a.length)===2){s=a[0]
s.toString
s=A.A(s)==="bigint"}else s=!1
if(s){s=a[1]
s.toString
return A.hU(A.A(s),null)}if(A.c(a.length)===2){s=a[0]
s.toString
s=A.A(s)==="real"}else s=!1
if(s){s=a[1]
s.toString
return new A.ci(A.Q(s))}}throw A.d(B.aj)},
jO(a){var s,r,q
a.toString
s=t.c
s.a(a)
r=a[0]
r.toString
A.A(r)
q=a[1]
q.toString
s.a(q)
s=t.X
q=B.b.ak(q,A.n5(),s)
q=A.da(q,q.$ti.h("V.E"))
return new A.eV(r,A.db(q,s))},
jP(a){var s,r=a.b,q=A.am(r),p=q.h("a5<1,h>")
r=A.da(new A.a5(r,q.h("h(1)").a(new A.hp()),p),p.h("V.E"))
q=a.a
p=A.am(q)
s=p.h("a5<1,r<e?>>")
q=A.da(new A.a5(q,p.h("r<e?>(1)").a(new A.hq()),s),s.h("V.E"))
return A.x([r,q,a.c],t.f)},
hp:function hp(){},
hq:function hq(){},
ky(a){var s
A:{if(a instanceof A.aj){s=a
break A}if(typeof a=="string"){s=A.eC(a)
break A}s=A.u(B.a1)}return s},
kx(a){var s
A:{if(a instanceof A.aq){s=a
break A}if(typeof a=="string"){s=A.iK(a)
break A}s=A.u(B.a5)}return s},
ay(a){var s
A:{if(typeof a=="string"){s=A.iw(a)
break A}if(A.bJ(a)){s=A.bt(A.O(a),0)
break A}if(a instanceof A.z){s=A.bt(a,0)
break A}s=A.u(B.a7)}return s},
iQ(a,b,c){return new A.a0(a,b)},
kB(a,b){return new A.az(a,b)},
bt(a,b){var s=a.m(0,$.E())
if(s===0)return $.ib()
s=a.a
return A.iv((s?a.D(0):a).i(0),s,b)},
iw(a){var s,r,q,p,o=a.length
if(o>147487)throw A.d(B.a2)
s=$.jY().a3(a)
r=!0
if(s!=null)if(s.ga8()===o){o=s.b
r=o.length
if(2>=r)return A.b(o,2)
if(o[2].length===0){if(3>=r)return A.b(o,3)
o=o[3]
o=(o==null?"":o).length===0}else o=!1}else o=r
else o=r
if(o)throw A.d(B.X)
o=s.b
if(4>=o.length)return A.b(o,4)
r=o[4]
q=A.iS(r==null?"0":r,null)
if(q==null||q<-147455||q>147455)throw A.d(B.a6)
if(3>=o.length)return A.b(o,3)
p=o[3]
if(p==null)p=""
return A.iv(A.n(o[2])+p,o[1]==="-",p.length-q)},
hA(a){var s,r
try{s=A.iw(a)
return s}catch(r){s=A.I(r)
if(s instanceof A.v)return null
else if(t.G.b(s))return null
else throw r}},
iv(a,b,c){var s,r,q,p=a.length,o=0
for(;;){if(!(o<p&&a.charCodeAt(o)===48))break;++o}if(o===p)return $.ib()
if(c<-131072||c>16383+p)throw A.d(A.aV("Decimal scale is out of range."))
s=p
for(;;){r=s-1
if(!(r>=0))return A.b(a,r)
if(!(a.charCodeAt(r)===48))break;--c
s=r}if(c>16383||s-o-c>131072)throw A.d(A.aV("Decimal exceeds the supported finite NUMERIC range."))
q=b?"-":""
return new A.az(A.hU(q+B.c.a1(a,o,s),null),c)},
hB(a){if(a<-131072||a>16383)throw A.d(A.P(a,-131072,16383,"scale",null))},
ix(a,b){if(a<1||a>1000||b<-1000||b>1000)throw A.d(A.J("Decimal precision must be 1..1000 and scale -1000..1000.",null))},
hz(a,b,c,d){var s,r,q=a.ad(0,b),p=a.dl(0,b),o=p.m(0,$.E())
if(o!==0){s=a.gU(0)*b.gU(0)
o=p.a?p.D(0):p
o=o.q(0,$.ih())
r=o.m(0,b.a?b.D(0):b)
o=!1
switch(d.a){case 0:o=A.u(B.W)
break
case 1:break
case 2:o=s<0
break
case 3:o=s>0
break
case 4:o=r>=0
break
case 5:if(r<=0){if(r===0){if(q.c!==0){o=q.b
if(0>=o.length)return A.b(o,0)
o=(o[0]&1)===0}else o=!0
o=!o}}else o=!0
break
default:o=null}if(o)q=q.S(0,A.O(s))}return A.bt(q,c)},
hY(a){var s
A:{if(a instanceof A.a3){s=A.fR(a)
break A}if(typeof a=="string"){s=A.ml(a)
break A}s=A.u(B.a4)}return s},
fR(a){var s=a.dt(),r=a.a,q=!0
if(r>=-2108668032e5)if(r<=864e13)q=r===864e13&&s.b!==0
if(q)throw A.d(B.w)
return s},
jq(a){var s=A.fR(t.k.a(a)),r=A.hG(A.eO(s),A.eM(s),A.eJ(s)),q=A.eB(A.eK(s),A.eL(s),A.eN(s),A.hJ(s)*1000+s.b),p=r.gaB(),o=q.i(0),n=r.a<=0?" BC":""
return p+" "+o+"+00"+n},
ml(a3){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0=1e6,a1=864e8,a2=$.ki().a3(a3)
if(a2==null||a2.ga8()!==a3.length)throw A.d(B.a_)
try{e=a2.b
if(1>=e.length)return A.b(e,1)
e=e[1]
e.toString
s=A.aa(e)
e=a2.b
if(6>=e.length)return A.b(e,6)
if(e[6]!=null){e=s
if(typeof e!=="number")return e.e9()
if(e<=0)throw A.d(B.V)
e=s
if(typeof e!=="number")return A.he(e)
s=1-e}e=a2.b
if(2>=e.length)return A.b(e,2)
e=e[2]
e.toString
r=A.aa(e)
e=a2.b
if(3>=e.length)return A.b(e,3)
e=e[3]
e.toString
q=A.aa(e)
e=r
if(typeof e!=="number")return e.b1()
d=!0
if(!(e<1)){e=r
if(typeof e!=="number")return e.a5()
if(!(e>12)){e=q
if(typeof e!=="number")return e.b1()
if(!(e<1)){e=q
d=A.iN(s,r)
if(typeof e!=="number")return e.a5()
d=e>d
e=d}else e=d}else e=d}else e=d
if(e)throw A.d(B.T)
e=a2.b
if(5>=e.length)return A.b(e,5)
p=e[5]
o=0
if(p!=null&&p.toUpperCase()!=="Z"){e=B.c.b8(p,1)
n=A.mZ(e,":","")
m=A.aa(J.hv(n,0,2))
l=J.ac(n)>=4?A.aa(J.hv(n,2,4)):0
k=J.ac(n)===6?A.aa(J.hv(n,4,6)):0
e=m
if(typeof e!=="number")return e.a5()
d=!0
if(!(e>15)){e=l
if(typeof e!=="number")return e.a5()
if(!(e>59)){e=k
if(typeof e!=="number")return e.a5()
e=e>59}else e=d}else e=d
if(e)throw A.d(B.a0)
e=m
if(typeof e!=="number")return e.q()
d=l
if(typeof d!=="number")return A.he(d)
c=k
if(typeof c!=="number")return A.he(c)
b=p
if(0>=b.length)return A.b(b,0)
b=b[0]==="-"?-1:1
o=((e*60+d)*60+c)*1e6*b}e=a2.b
if(4>=e.length)return A.b(e,4)
e=e[4]
e.toString
e=A.eC(e)
d=o
if(typeof d!=="number")return A.he(d)
j=e.a-d
i=A.ju(s,r,q)+A.fS(j,a1)
d=j
if(typeof d!=="number")return d.n()
h=B.l.n(d,a1)
e=i
if(typeof e!=="number")return e.b1()
d=!0
if(!(e<0)){e=i
if(typeof e!=="number")return e.a5()
if(!(e>102440588))e=J.ab(i,102440588)&&!J.ab(h,0)
else e=d}else e=d
if(e)throw A.d(B.w)
g=A.iL(i)
f=A.hH(h)
e=A.it(g.a,g.b,g.c,B.a.l(f.a,36e8),B.a.n(B.a.l(f.a,6e7),60),B.a.n(B.a.l(f.a,a0),60),B.a.l(B.a.n(f.a,a0),1000),B.a.n(B.a.n(f.a,a0),1000))
return e}catch(a){if(t.G.b(A.I(a)))throw A.d(B.S)
else throw a}},
fS(a,b){var s=B.a.ad(a,b)
return s-(a<0&&B.a.n(a,b)!==0?1:0)},
ju(a,b,c){var s=a-(b<=2?1:0),r=A.fS(s,400),q=s-r*400,p=b>2?-3:9
return r*146097+q*365+B.a.l(q,4)-B.a.l(q,100)+B.a.l(153*(b+p)+2,5)+c-1+1721120},
hG(a,b,c){var s
if(a<-4713||a>5874897||b<1||b>12||c<1||c>A.iN(a,b))throw A.d(A.aV("Invalid Gregorian date."))
s=A.ju(a,b,c)
if(s<0||s>2147483493)throw A.d(A.aV("Date exceeds the finite PostgreSQL DATE range."))
return new A.ap(a,b,c,s)},
iL(a){var s,r,q,p,o,n,m,l,k
if(a<0||a>2147483493)throw A.d(A.P(a,0,2147483493,"julianDay",null))
s=a-1721120
r=A.fS(s,146097)
q=s-r*146097
p=B.a.l(q-B.a.l(q,1460)+B.a.l(q,36524)-B.a.l(q,146096),365)
o=q-(365*p+B.a.l(p,4)-B.a.l(p,100))
n=B.a.l(5*o+2,153)
m=B.a.l(153*n+2,5)
l=n+(n<10?3:-9)
k=l<=2?1:0
return new A.ap(p+r*400+k,l,o-m+1,a)},
iM(a){var s,r,q,p=$.k_().a3(a)
if(p==null||p.ga8()!==a.length)throw A.d(B.Y)
s=p.b
if(1>=s.length)return A.b(s,1)
r=s[1]
r.toString
q=A.aa(r)
if(4>=s.length)return A.b(s,4)
if(s[4]!=null){if(q<=0)throw A.d(B.a3)
q=1-q}r=s[2]
r.toString
r=A.aa(r)
if(3>=s.length)return A.b(s,3)
s=s[3]
s.toString
return A.hG(q,r,A.aa(s))},
kS(a){var s,r
try{s=A.iM(a)
return s}catch(r){s=A.I(r)
if(s instanceof A.v)return null
else if(t.G.b(s))return null
else throw r}},
iN(a,b){var s
A:{if(2===b){if(B.a.n(a,4)===0)s=B.a.n(a,100)!==0||B.a.n(a,400)===0
else s=!1
s=s?29:28
break A}if(4===b||6===b||9===b||11===b){s=30
break A}s=31
break A}return s},
eB(a,b,c,d){var s=!0
if(a>=0)if(a<=24)if(b>=0)if(b<=59)if(c>=0)if(c<=59)if(d>=0)if(d<=999999)if(a===24)s=b!==0||c!==0||d!==0
else s=!1
if(s)throw A.d(A.aV("Invalid time of day."))
return new A.aj(((a*60+b)*60+c)*1e6+d)},
hH(a){if(a<0||a>864e8)throw A.d(A.P(a,0,864e8,"microseconds",null))
return new A.aj(a)},
eC(a){var s,r,q,p,o=$.k0().a3(a)
if(o==null||o.ga8()!==a.length)throw A.d(B.Z)
s=o.b
if(1>=s.length)return A.b(s,1)
r=s[1]
r.toString
r=A.aa(r)
if(2>=s.length)return A.b(s,2)
q=s[2]
q.toString
q=A.aa(q)
if(3>=s.length)return A.b(s,3)
p=s[3]
p=A.aa(p==null?"0":p)
if(4>=s.length)return A.b(s,4)
s=s[4]
return A.eB(r,q,p,A.aa(B.c.dk(s==null?"":s,6,"0")))},
kT(a){var s,r
try{s=A.eC(a)
return s}catch(r){s=A.I(r)
if(s instanceof A.v)return null
else if(t.G.b(s))return null
else throw r}},
hF(a,b){if(B.a.l(b.a,36e8)===24){a=a.bs(1)
b=A.eB(0,0,0,0)}if(a.d>109203527)throw A.d(A.aV("Local timestamp exceeds the finite PostgreSQL TIMESTAMP range."))
return new A.aq(a,b)},
iK(a){var s,r,q,p=$.jZ().a3(a)
if(p==null||p.ga8()!==a.length)throw A.d(B.U)
s=p.b
r=s.length
if(1>=r)return A.b(s,1)
q=s[1]
if(3>=r)return A.b(s,3)
r=s[3]
if(r==null)r=""
r=A.iM(A.n(q)+r)
if(2>=s.length)return A.b(s,2)
s=s[2]
s.toString
return A.hF(r,A.eC(s))},
kR(a){var s,r
try{s=A.iK(a)
return s}catch(r){s=A.I(r)
if(s instanceof A.v)return null
else if(t.G.b(s))return null
else throw r}},
jC(a,b,c){var s,r,q
if(b<0||b>6)A.u(A.P(b,0,6,"digits",null))
if(!(b>=0&&b<7))return A.b(B.x,b)
s=B.x[b]
r=B.a.n(a,s)
q=r*2
if(q<=s)q=q===s&&!c
else q=!0
return q?s-r:-r},
ci:function ci(a){this.a=a},
hy:function hy(a,b,c){this.c=a
this.d=b
this.$ti=c},
a0:function a0(a,b){this.a=a
this.b=b},
aA:function aA(a,b){this.a=a
this.b=b},
az:function az(a,b){this.a=a
this.b=b},
ap:function ap(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
aj:function aj(a){this.a=a},
aq:function aq(a,b){this.a=a
this.b=b},
l7(a,b,c,d,e,f,g){return new A.ck(d,b,c,e,f,a,g)},
ck:function ck(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g},
eY:function eY(){},
ao:function ao(a,b){this.a=a
this.$ti=b},
b5:function b5(a){this.a=a},
hZ(a,b,c){var s,r,q=new A.dz(c,A.iJ(c.b,null,!1,t.X))
try{A.i_(a,b.$1(q))}catch(r){s=A.I(r)
a.b6(A.bX(s))}finally{}},
js(a,b){var s,r
try{A.i_(a,b.$0())}catch(r){s=A.I(r)
a.b6(A.bX(s))}},
i_(a,b){var s,r,q,p
A:{s=null
if(b==null){a.a.d.sqlite3_result_null(a.b)
break A}if(A.bJ(b)){a.a.d.sqlite3_result_int64(a.b,t.C.a(v.G.BigInt(A.O(b).i(0))))
break A}if(b instanceof A.z){a.a.d.sqlite3_result_int64(a.b,t.C.a(v.G.BigInt(A.il(b).i(0))))
break A}if(typeof b=="number"){a.a.d.sqlite3_result_double(a.b,b)
break A}if(A.cI(b)){a.a.d.sqlite3_result_int64(a.b,t.C.a(v.G.BigInt(A.O(b?1:0).i(0))))
break A}if(typeof b=="string"){r=B.h.P(b)
q=a.a
p=q.a2(r)
q=q.d
q.sqlite3_result_text(a.b,p,r.length,-1)
q.dart_sqlite3_free(p)
break A}q=t.L
if(q.b(b)){q.a(b)
q=a.a
p=q.a2(b)
q=q.d
q.sqlite3_result_blob64(a.b,p,t.C.a(v.G.BigInt(J.ac(b))),-1)
q.dart_sqlite3_free(p)
break A}if(t.u.b(b)){A.i_(a,b.a)
a.a.d.sqlite3_result_subtype(a.b,b.b)
break A}s=A.u(A.ax(b,"result","Unsupported type"))}return s},
cY:function cY(a,b,c){var _=this
_.a=a
_.b=b
_.c=c
_.r=!1},
eq:function eq(a,b){this.a=a
this.b=b},
er:function er(a,b){this.a=a
this.b=b},
es:function es(a,b){this.a=a
this.b=b},
eo:function eo(a,b){this.a=a
this.b=b},
ep:function ep(a,b,c){this.a=a
this.b=b
this.c=c},
en:function en(a,b){this.a=a
this.b=b},
ek:function ek(a,b,c){this.a=a
this.b=b
this.c=c},
em:function em(a,b){this.a=a
this.b=b},
el:function el(a,b){this.a=a
this.b=b},
et:function et(a){this.a=a},
ej:function ej(a,b){this.a=a
this.b=b},
dz:function dz(a,b){this.a=a
this.b=b},
eX:function eX(){},
bB:function bB(a,b,c){var _=this
_.a=a
_.b=b
_.d=c
_.e=null
_.f=!0
_.r=!1
_.w=null},
dE:function dE(a,b,c){var _=this
_.r=a
_.w=-1
_.x=$
_.y=!1
_.a=b
_.c=c},
iC(){var s=$.hs()
return new A.d1(A.d9(t.N,t.fN),s,"dart-memory")},
d1:function d1(a,b,c){this.d=a
this.b=b
this.a=c},
dO:function dO(a,b,c){var _=this
_.a=a
_.b=b
_.c=c
_.d=0},
mV(a){return new A.cp(A.x(A.A(A.B(new v.G.URL(a,"file:///")).pathname).split("/"),t.s),t.bB.a(new A.hk()),t.cc)},
hk:function hk(){},
bs:function bs(){},
c_:function c_(){},
dq:function dq(a,b,c){this.d=a
this.a=b
this.c=c},
N:function N(a,b){this.a=a
this.b=b},
dS:function dS(a){this.a=a
this.b=-1},
dT:function dT(){},
dU:function dU(){},
dW:function dW(){},
dX:function dX(){},
eH:function eH(a,b){this.a=a
this.b=b},
cU:function cU(){},
b7:function b7(a){this.a=a},
f3(a){return new A.aZ(a)},
ik(a,b){var s,r,q
if(b==null)b=$.hs()
for(s=a.length,r=0;r<s;++r){q=b.bK(256)
a.$flags&2&&A.l(a)
a[r]=q}},
aZ:function aZ(a){this.a=a},
eW:function eW(a){this.a=a},
H:function H(){},
cR:function cR(){},
cQ:function cQ(){},
dC:function dC(a){this.a=a},
dA:function dA(a,b,c){this.a=a
this.b=b
this.c=c},
fc:function fc(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
dD:function dD(a,b,c){this.b=a
this.c=b
this.d=c},
b_:function b_(a,b,c){this.a=a
this.b=b
this.c=c},
au:function au(a,b){this.a=a
this.b=b},
bC:function bC(a,b,c){this.a=a
this.b=b
this.c=c},
a8(a){var s,r,q
try{a.$0()
return 0}catch(r){q=A.I(r)
if(q instanceof A.aZ){s=q
return s.a}else return 1}},
cX:function cX(a){var _=this
_.b=_.a=$
_.c=1
_.d=a},
e8:function e8(a,b,c){this.a=a
this.b=b
this.c=c},
e5:function e5(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
ea:function ea(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
ec:function ec(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
ee:function ee(a,b){this.a=a
this.b=b},
e7:function e7(a){this.a=a},
ed:function ed(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
ei:function ei(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
eg:function eg(a,b){this.a=a
this.b=b},
ef:function ef(a,b){this.a=a
this.b=b},
e9:function e9(a,b,c){this.a=a
this.b=b
this.c=c},
eb:function eb(a,b){this.a=a
this.b=b},
eh:function eh(a,b){this.a=a
this.b=b},
e6:function e6(a,b,c){this.a=a
this.b=b
this.c=c},
a7:function a7(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
f9:function f9(a){this.a=a},
fa:function fa(a){this.a=a},
fb(a,b){var s=0,r=A.aM(t.ab),q,p,o,n,m
var $async$fb=A.aN(function(c,d){if(c===1)return A.aI(d,r)
for(;;)switch(s){case 0:p=new A.cX(A.d9(t.S,t.E))
o=A
n=A
m=A
s=3
return A.R(new A.f9(p).aj(a),$async$fb)
case 3:q=new o.dB(new n.dC(m.le(d,p)))
s=1
break
case 1:return A.aJ(q,r)}})
return A.aK($async$fb,r)},
dB:function dB(a){this.a=a},
ds(a,b){var s=0,r=A.aM(t.cf),q,p,o,n,m,l,k,j
var $async$ds=A.aN(function(c,d){if(c===1)return A.aI(d,r)
for(;;)switch(s){case 0:j=A.jR()
if(j==null)throw A.d(A.f3(1))
p=t.m
s=3
return A.R(A.bP(A.B(j.getDirectory()),p),$async$ds)
case 3:o=d
n=A.mV(a),m=J.cN(n.a),n=new A.bh(m,n.b,n.$ti.h("bh<1>")),l=null
case 4:if(!n.p()){s=6
break}s=7
return A.R(A.bP(A.B(o.getDirectoryHandle(m.gv(),{create:!0})),p),$async$ds)
case 7:k=d
case 5:l=o,o=k
s=4
break
case 6:q=new A.cy(l,o)
s=1
break
case 1:return A.aJ(q,r)}})
return A.aK($async$ds,r)},
eU(a){var s=0,r=A.aM(t.m),q
var $async$eU=A.aN(function(b,c){if(b===1)return A.aI(c,r)
for(;;)switch(s){case 0:s=3
return A.R(A.ds(a,!0),$async$eU)
case 3:q=c.b
s=1
break
case 1:return A.aJ(q,r)}})
return A.aK($async$eU,r)},
eS(a){var s=0,r=A.aM(t.h),q,p
var $async$eS=A.aN(function(b,c){if(b===1)return A.aI(c,r)
for(;;)switch(s){case 0:if(A.jR()==null)throw A.d(A.f3(1))
p=A
s=3
return A.R(A.eU(a),$async$eS)
case 3:q=p.eR(c,!1,"simple-opfs")
s=1
break
case 1:return A.aJ(q,r)}})
return A.aK($async$eS,r)},
eR(a,b,c){var s=0,r=A.aM(t.h),q,p,o,n
var $async$eR=A.aN(function(d,e){if(d===1)return A.aI(e,r)
for(;;)switch(s){case 0:p=A.iC()
o=$.hs()
n=new A.cg(p,o,c)
s=3
return A.R(n.a4(a,!1),$async$eR)
case 3:q=n
s=1
break
case 1:return A.aJ(q,r)}})
return A.aK($async$eR,r)},
bu:function bu(a,b,c){this.c=a
this.a=b
this.b=c},
cg:function cg(a,b,c){var _=this
_.d=null
_.e=a
_.b=b
_.a=c},
eT:function eT(a,b){this.a=a
this.b=b},
dY:function dY(a,b,c){var _=this
_.a=a
_.b=b
_.c=c
_.d=0},
fB:function fB(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
le(a,b){var s=A.B(A.B(a.exports).memory)
b.b!==$&&A.jS()
b.b=s
s=new A.f4(s,b,A.B(a.exports))
s.c9(a,b)
return s},
hO(a,b){var s=A.ar(t.a.a(a.buffer),b,null),r=s.length,q=0
for(;;){if(!(q<r))return A.b(s,q)
if(!(s[q]!==0))break;++q}return q},
av(a,b,c){var s=t.a.a(a.buffer)
return B.r.bB(A.ar(s,b,c==null?A.hO(a,b):c))},
hN(a,b,c){var s
if(b===0)return null
s=t.a.a(a.buffer)
return B.r.bB(A.ar(s,b,c==null?A.hO(a,b):c))},
j_(a,b,c){var s=new Uint8Array(c)
B.e.b3(s,0,A.ar(t.a.a(a.buffer),b,c))
return s},
f4:function f4(a,b,c){var _=this
_.b=a
_.c=b
_.d=c
_.w=_.r=null},
f5:function f5(a){this.a=a},
f6:function f6(a){this.a=a},
f7:function f7(a){this.a=a},
f8:function f8(a){this.a=a},
aG:function aG(){},
dP:function dP(){},
bf:function bf(a,b){this.a=a
this.b=b},
jT(a){return v.mangledGlobalNames[a]},
mW(a){if(typeof dartPrint=="function"){dartPrint(a)
return}if(typeof console=="object"&&typeof console.log!="undefined"){console.log(a)
return}if(typeof print=="function"){print(a)
return}throw"Unable to print message: "+String(a)},
kO(a,b,c,d,e,f){var s=a[b](c,d,e)
return s},
i6(a,b,c,d,e,f){var s,r,q=b.a,p=b.b,o=q.d,n=A.c(o.sqlite3_extended_errcode(p)),m=A.c(o.sqlite3_error_offset(p))
A:{if(m<0){s=null
break A}s=m
break A}r=a.a
return new A.ck(A.av(q.b,A.c(o.sqlite3_errmsg(p)),null),A.av(r.b,A.c(r.d.sqlite3_errstr(n)),null)+" (code "+n+")",c,s,d,e,f)},
cM(a,b,c,d,e){throw A.d(A.i6(a.a,a.b,b,c,d,e))},
il(a){if(a.m(0,$.jW())<0||a.m(0,$.jV())>0)throw A.d(A.iz("BigInt value exceeds the range of 64 bits"))
return a},
i7(a,b,c){var s=a?2049:1
if(b)s|=524288
return s},
l3(a){var s,r,q=a.a,p=a.b,o=q.d,n=A.c(o.sqlite3_value_type(p))
A:{s=null
if(1===n){q=A.c(A.Q(v.G.Number(t.C.a(o.sqlite3_value_int64(p)))))
break A}if(2===n){q=A.Q(o.sqlite3_value_double(p))
break A}if(3===n){r=A.c(o.sqlite3_value_bytes(p))
q=A.av(q.b,A.c(o.sqlite3_value_text(p)),r)
break A}if(4===n){r=A.c(o.sqlite3_value_bytes(p))
q=A.j_(q.b,A.c(o.sqlite3_value_blob(p)),r)
break A}q=s
break A}return q},
kH(a,b){var s,r,q,p="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ012346789"
for(s=b,r=0;r<16;++r,s=q){q=a.bK(61)
if(!(q<61))return A.b(p,q)
q=s+A.bz(p.charCodeAt(q))}return s.charCodeAt(0)==0?s:s},
jR(){var s=A.B(v.G.navigator)
if("storage" in s)return A.B(s.storage)
return null},
iA(a,b,c){var s=A.c(a.read(b,c))
return s},
iB(a,b,c){var s=A.c(a.write(b,c))
return s},
mT(){return A.mX()}},B={}
var w=[A,J,B]
var $={}
A.hC.prototype={}
J.d3.prototype={
I(a,b){return a===b},
gu(a){return A.dm(a)},
i(a){return"Instance of '"+A.dn(a)+"'"},
gF(a){return A.bn(A.i1(this))}}
J.d5.prototype={
i(a){return String(a)},
gu(a){return a?519018:218159},
gF(a){return A.bn(t.v)},
$io:1,
$iaO:1}
J.c1.prototype={
I(a,b){return null==b},
i(a){return"null"},
gu(a){return 0},
$io:1}
J.c2.prototype={$ip:1}
J.aT.prototype={
gu(a){return 0},
i(a){return String(a)}}
J.dl.prototype={}
J.bg.prototype={}
J.aB.prototype={
i(a){var s=a[$.jX()]
if(s==null)s=a[$.bQ()]
if(s==null)return this.c8(a)
return"JavaScript function for "+J.b4(s)},
$ib6:1}
J.U.prototype={
gu(a){return 0},
i(a){return String(a)}}
J.bw.prototype={
gu(a){return 0},
i(a){return String(a)}}
J.r.prototype={
t(a,b){A.am(a).c.a(b)
a.$flags&1&&A.l(a,29)
a.push(b)},
ak(a,b,c){var s=A.am(a)
return new A.a5(a,s.E(c).h("1(2)").a(b),s.h("@<1>").E(c).h("a5<1,2>"))},
aq(a,b){return A.iX(a,b,null,A.am(a).c)},
H(a,b){if(!(b>=0&&b<a.length))return A.b(a,b)
return a[b]},
gd5(a){if(a.length>0)return a[0]
throw A.d(A.ex())},
gda(a){var s=a.length
if(s>0)return a[s-1]
throw A.d(A.ex())},
ga_(a){var s=a.length
if(s===1){if(0>=s)return A.b(a,0)
return a[0]}if(s===0)throw A.d(A.ex())
throw A.d(A.iE())},
dc(a,b){var s,r=a.length,q=r-1
if(q<0)return-1
q<r
for(s=q;s>=0;--s){if(!(s<a.length))return A.b(a,s)
if(J.ab(a[s],b))return s}return-1},
i(a){return A.iF(a,"[","]")},
gG(a){return new J.bR(a,a.length,A.am(a).h("bR<1>"))},
gu(a){return A.dm(a)},
gk(a){return a.length},
j(a,b){if(!(b>=0&&b<a.length))throw A.d(A.ha(a,b))
return a[b]},
A(a,b,c){A.am(a).c.a(c)
a.$flags&2&&A.l(a)
if(!(b>=0&&b<a.length))throw A.d(A.ha(a,b))
a[b]=c},
$ii:1,
$if:1,
$ij:1}
J.d4.prototype={
du(a){var s,r,q
if(!Array.isArray(a))return null
s=a.$flags|0
if((s&4)!==0)r="const, "
else if((s&2)!==0)r="unmodifiable, "
else r=(s&1)!==0?"fixed, ":""
q="Instance of '"+A.dn(a)+"'"
if(r==="")return q
return q+" ("+r+"length: "+a.length+")"}}
J.ey.prototype={}
J.bR.prototype={
gv(){var s=this.d
return s==null?this.$ti.c.a(s):s},
p(){var s,r=this,q=r.a,p=q.length
if(r.b!==p){q=A.hr(q)
throw A.d(q)}s=r.c
if(s>=p){r.d=null
return!1}r.d=q[s]
r.c=s+1
return!0},
$iK:1}
J.bv.prototype={
m(a,b){var s
A.jn(b)
if(a<b)return-1
else if(a>b)return 1
else if(a===b){if(a===0){s=this.gaY(b)
if(this.gaY(a)===s)return 0
if(this.gaY(a))return-1
return 1}return 0}else if(isNaN(a)){if(isNaN(b))return 0
return 1}else return-1},
gaY(a){return a===0?1/a<0:a<0},
bP(a){var s
if(a>=-2147483648&&a<=2147483647)return a|0
if(isFinite(a)){s=a<0?Math.ceil(a):Math.floor(a)
return s+0}throw A.d(A.aY(""+a+".toInt()"))},
cE(a){var s,r
if(a>=0){if(a<=2147483647){s=a|0
return a===s?s:s+1}}else if(a>=-2147483648)return a|0
r=Math.ceil(a)
if(isFinite(r))return r
throw A.d(A.aY(""+a+".ceil()"))},
i(a){if(a===0&&1/a<0)return"-0.0"
else return""+a},
gu(a){var s,r,q,p,o=a|0
if(a===o)return o&536870911
s=Math.abs(a)
r=Math.log(s)/0.6931471805599453|0
q=Math.pow(2,r)
p=s<1?s/q:q/s
return((p*9007199254740992|0)+(p*3542243181176521|0))*599197+r*1259&536870911},
n(a,b){var s=a%b
if(s===0)return 0
if(s>0)return s
return s+b},
ad(a,b){if((a|0)===a)if(b>=1||b<-1)return a/b|0
return this.bo(a,b)},
l(a,b){return(a|0)===a?a/b|0:this.bo(a,b)},
bo(a,b){var s=a/b
if(s>=-2147483648&&s<=2147483647)return s|0
if(s>0){if(s!==1/0)return Math.floor(s)}else if(s>-1/0)return Math.ceil(s)
throw A.d(A.aY("Result of truncating division is "+A.n(s)+": "+A.n(a)+" ~/ "+b))},
O(a,b){if(b<0)throw A.d(A.i4(b))
return b>31?0:a<<b>>>0},
Z(a,b){var s
if(b<0)throw A.d(A.i4(b))
if(a>0)s=this.bm(a,b)
else{s=b>31?31:b
s=a>>s>>>0}return s},
B(a,b){var s
if(a>0)s=this.bm(a,b)
else{s=b>31?31:b
s=a>>s>>>0}return s},
bm(a,b){return b>31?0:a>>>b},
gF(a){return A.bn(t.o)},
$it:1,
$im:1,
$ia2:1}
J.c0.prototype={
gbw(a){var s,r=a<0?-a-1:a,q=r
for(s=32;q>=4294967296;){q=this.l(q,4294967296)
s+=32}return s-Math.clz32(q)},
gF(a){return A.bn(t.S)},
$io:1,
$ia:1}
J.d6.prototype={
gF(a){return A.bn(t.i)},
$io:1}
J.aS.prototype={
c7(a,b){var s=b.length
if(s>a.length)return!1
return b===a.substring(0,s)},
a1(a,b,c){return a.substring(b,A.dp(b,c,a.length))},
b8(a,b){return this.a1(a,b,null)},
q(a,b){var s,r
if(0>=b)return""
if(b===1||a.length===0)return a
if(b!==b>>>0)throw A.d(B.J)
for(s=a,r="";;){if((b&1)===1)r=s+r
b=b>>>1
if(b===0)break
s+=s}return r},
R(a,b,c){var s=b-a.length
if(s<=0)return a
return this.q(c,s)+a},
dk(a,b,c){var s=b-a.length
if(s<=0)return a
return a+this.q(c,s)},
m(a,b){var s
A.A(b)
if(a===b)s=0
else s=a<b?-1:1
return s},
i(a){return a},
gu(a){var s,r,q
for(s=a.length,r=0,q=0;q<s;++q){r=r+a.charCodeAt(q)&536870911
r=r+((r&524287)<<10)&536870911
r^=r>>6}r=r+((r&67108863)<<3)&536870911
r^=r>>11
return r+((r&16383)<<15)&536870911},
gF(a){return A.bn(t.N)},
gk(a){return a.length},
$io:1,
$it:1,
$ieI:1,
$ih:1}
A.bx.prototype={
i(a){return"LateInitializationError: "+this.a}}
A.eP.prototype={}
A.i.prototype={}
A.V.prototype={
gG(a){var s=this
return new A.b9(s,s.gk(s),A.S(s).h("b9<V.E>"))},
bJ(a,b){var s,r,q,p=this,o=p.gk(p)
if(b.length!==0){if(o===0)return""
s=A.n(p.H(0,0))
if(o!==p.gk(p))throw A.d(A.aQ(p))
for(r=s,q=1;q<o;++q){r=r+b+A.n(p.H(0,q))
if(o!==p.gk(p))throw A.d(A.aQ(p))}return r.charCodeAt(0)==0?r:r}else{for(q=0,r="";q<o;++q){r+=A.n(p.H(0,q))
if(o!==p.gk(p))throw A.d(A.aQ(p))}return r.charCodeAt(0)==0?r:r}},
d9(a){return this.bJ(0,"")}}
A.cn.prototype={
gcm(){var s=J.ac(this.a),r=this.c
if(r==null||r>s)return s
return r},
gcz(){var s=J.ac(this.a),r=this.b
if(r>s)return s
return r},
gk(a){var s,r=J.ac(this.a),q=this.b
if(q>=r)return 0
s=this.c
if(s==null||s>=r)return r-q
return s-q},
H(a,b){var s=this,r=s.gcz()+b
if(b<0||r>=s.gcm())throw A.d(A.ew(b,s.gk(0),s,null,"index"))
return J.ij(s.a,r)},
bQ(a,b){var s,r,q,p=this,o=p.b,n=p.a,m=J.cL(n),l=m.gk(n),k=p.c
if(k!=null&&k<l)l=k
s=l-o
if(s<=0){n=J.iH(0,p.$ti.c)
return n}r=A.iJ(s,m.H(n,o),!1,p.$ti.c)
for(q=1;q<s;++q){B.b.A(r,q,m.H(n,o+q))
if(m.gk(n)<l)throw A.d(A.aQ(p))}return r}}
A.b9.prototype={
gv(){var s=this.d
return s==null?this.$ti.c.a(s):s},
p(){var s,r=this,q=r.a,p=J.cL(q),o=p.gk(q)
if(r.b!==o)throw A.d(A.aQ(q))
s=r.c
if(s>=o){r.d=null
return!1}r.d=p.H(q,s);++r.c
return!0},
$iK:1}
A.bb.prototype={
gG(a){var s=this.a
return new A.c6(s.gG(s),this.b,A.S(this).h("c6<1,2>"))},
gk(a){var s=this.a
return s.gk(s)}}
A.bV.prototype={$ii:1}
A.c6.prototype={
p(){var s=this,r=s.b
if(r.p()){s.a=s.c.$1(r.gv())
return!0}s.a=null
return!1},
gv(){var s=this.a
return s==null?this.$ti.y[1].a(s):s},
$iK:1}
A.a5.prototype={
gk(a){return J.ac(this.a)},
H(a,b){return this.b.$1(J.ij(this.a,b))}}
A.cp.prototype={
gG(a){return new A.bh(J.cN(this.a),this.b,this.$ti.h("bh<1>"))}}
A.bh.prototype={
p(){var s,r
for(s=this.a,r=this.b;s.p();)if(r.$1(s.gv()))return!0
return!1},
gv(){return this.a.gv()},
$iK:1}
A.bd.prototype={
gG(a){var s=this.a
return new A.ch(s.gG(s),this.b,A.S(this).h("ch<1>"))}}
A.bW.prototype={
gk(a){var s=this.a,r=s.gk(s)-this.b
if(r>=0)return r
return 0},
$ii:1}
A.ch.prototype={
p(){var s,r
for(s=this.a,r=0;r<this.b;++r)s.p()
this.b=0
return s.p()},
gv(){return this.a.gv()},
$iK:1}
A.T.prototype={}
A.ce.prototype={
gk(a){return J.ac(this.a)},
H(a,b){var s=this.a,r=J.cL(s)
return r.H(s,r.gk(s)-1-b)}}
A.cy.prototype={$r:"+(1,2)",$s:1}
A.bF.prototype={$r:"+file,outFlags(1,2)",$s:2}
A.cz.prototype={$r:"+result,resultCode(1,2)",$s:3}
A.bT.prototype={
i(a){return A.hI(this)},
$iba:1}
A.bU.prototype={
gk(a){return this.b.length},
gcs(){var s=this.$keys
if(s==null){s=Object.keys(this.a)
this.$keys=s}return s},
a6(a){if("__proto__"===a)return!1
return this.a.hasOwnProperty(a)},
j(a,b){if(!this.a6(b))return null
return this.b[this.a[b]]},
aU(a,b){var s,r,q,p
this.$ti.h("~(1,2)").a(b)
s=this.gcs()
r=this.b
for(q=s.length,p=0;p<q;++p)b.$2(s[p],r[p])}}
A.cf.prototype={}
A.f_.prototype={
N(a){var s,r,q=this,p=new RegExp(q.a).exec(a)
if(p==null)return null
s=Object.create(null)
r=q.b
if(r!==-1)s.arguments=p[r+1]
r=q.c
if(r!==-1)s.argumentsExpr=p[r+1]
r=q.d
if(r!==-1)s.expr=p[r+1]
r=q.e
if(r!==-1)s.method=p[r+1]
r=q.f
if(r!==-1)s.receiver=p[r+1]
return s}}
A.cb.prototype={
i(a){return"Null check operator used on a null value"}}
A.d8.prototype={
i(a){var s,r=this,q="NoSuchMethodError: method not found: '",p=r.b
if(p==null)return"NoSuchMethodError: "+r.a
s=r.c
if(s==null)return q+p+"' ("+r.a+")"
return q+p+"' on '"+s+"' ("+r.a+")"}}
A.dw.prototype={
i(a){var s=this.a
return s.length===0?"Error":"Error: "+s}}
A.eF.prototype={
i(a){return"Throw of null ('"+(this.a===null?"null":"undefined")+"' from JavaScript)"}}
A.bY.prototype={}
A.cA.prototype={
i(a){var s,r=this.b
if(r!=null)return r
r=this.a
s=r!==null&&typeof r==="object"?r.stack:null
return this.b=s==null?"":s},
$iaW:1}
A.aP.prototype={
i(a){var s=this.constructor,r=s==null?null:s.name
return"Closure '"+A.jU(r==null?"unknown":r)+"'"},
$ib6:1,
ge8(){return this},
$C:"$1",
$R:1,
$D:null}
A.cS.prototype={$C:"$0",$R:0}
A.cT.prototype={$C:"$2",$R:2}
A.du.prototype={}
A.dt.prototype={
i(a){var s=this.$static_name
if(s==null)return"Closure of unknown static method"
return"Closure '"+A.jU(s)+"'"}}
A.br.prototype={
I(a,b){if(b==null)return!1
if(this===b)return!0
if(!(b instanceof A.br))return!1
return this.$_target===b.$_target&&this.a===b.a},
gu(a){return(A.jJ(this.a)^A.dm(this.$_target))>>>0},
i(a){return"Closure '"+this.$_name+"' of "+("Instance of '"+A.dn(this.a)+"'")}}
A.dr.prototype={
i(a){return"RuntimeError: "+this.a}}
A.c3.prototype={
gk(a){return this.a},
gaZ(){return new A.c5(this,A.S(this).h("c5<1>"))},
a6(a){var s=this.b
if(s==null)return!1
return s[a]!=null},
j(a,b){var s,r,q,p,o=null
if(typeof b=="string"){s=this.b
if(s==null)return o
r=s[b]
q=r==null?o:r.b
return q}else if(typeof b=="number"&&(b&0x3fffffff)===b){p=this.c
if(p==null)return o
r=p[b]
q=r==null?o:r.b
return q}else return this.d7(b)},
d7(a){var s,r,q=this.d
if(q==null)return null
s=this.cq(q,a)
r=this.aW(s,a)
if(r<0)return null
return s[r].b},
A(a,b,c){var s,r,q,p,o,n,m=this,l=A.S(m)
l.c.a(b)
l.y[1].a(c)
if(typeof b=="string"){s=m.b
m.ba(s==null?m.b=m.aL():s,b,c)}else if(typeof b=="number"&&(b&0x3fffffff)===b){r=m.c
m.ba(r==null?m.c=m.aL():r,b,c)}else{q=m.d
if(q==null)q=m.d=m.aL()
p=m.aV(b)
o=q[p]
if(o==null)q[p]=[m.aM(b,c)]
else{n=m.aW(o,b)
if(n>=0)o[n].b=c
else o.push(m.aM(b,c))}}},
am(a,b){var s=this
if(typeof b=="string")return s.bl(s.b,b)
else if(typeof b=="number"&&(b&0x3fffffff)===b)return s.bl(s.c,b)
else return s.d8(b)},
d8(a){var s,r,q,p,o=this,n=o.d
if(n==null)return null
s=o.aV(a)
r=n[s]
q=o.aW(r,a)
if(q<0)return null
p=r.splice(q,1)[0]
o.br(p)
if(r.length===0)delete n[s]
return p.b},
aU(a,b){var s,r,q=this
A.S(q).h("~(1,2)").a(b)
s=q.e
r=q.r
while(s!=null){b.$2(s.a,s.b)
if(r!==q.r)throw A.d(A.aQ(q))
s=s.c}},
ba(a,b,c){var s,r=A.S(this)
r.c.a(b)
r.y[1].a(c)
s=a[b]
if(s==null)a[b]=this.aM(b,c)
else s.b=c},
bl(a,b){var s
if(a==null)return null
s=a[b]
if(s==null)return null
this.br(s)
delete a[b]
return s.b},
aK(){this.r=this.r+1&1073741823},
aM(a,b){var s=this,r=A.S(s),q=new A.ez(r.c.a(a),r.y[1].a(b))
if(s.e==null)s.e=s.f=q
else{r=s.f
r.toString
q.d=r
s.f=r.c=q}++s.a
s.aK()
return q},
br(a){var s=this,r=a.d,q=a.c
if(r==null)s.e=q
else r.c=q
if(q==null)s.f=r
else q.d=r;--s.a
s.aK()},
aV(a){return J.ag(a)&1073741823},
cq(a,b){return a[this.aV(b)]},
aW(a,b){var s,r
if(a==null)return-1
s=a.length
for(r=0;r<s;++r)if(J.ab(a[r].a,b))return r
return-1},
i(a){return A.hI(this)},
aL(){var s=Object.create(null)
s["<non-identifier-key>"]=s
delete s["<non-identifier-key>"]
return s}}
A.ez.prototype={}
A.c5.prototype={
gk(a){return this.a.a},
gG(a){var s=this.a
return new A.c4(s,s.r,s.e,this.$ti.h("c4<1>"))}}
A.c4.prototype={
gv(){return this.d},
p(){var s,r=this,q=r.a
if(r.b!==q.r)throw A.d(A.aQ(q))
s=r.c
if(s==null){r.d=null
return!1}else{r.d=s.a
r.c=s.c
return!0}},
$iK:1}
A.eA.prototype={
gk(a){return this.a.a},
gG(a){var s=this.a
return new A.b8(s,s.r,s.e,this.$ti.h("b8<1>"))}}
A.b8.prototype={
gv(){return this.d},
p(){var s,r=this,q=r.a
if(r.b!==q.r)throw A.d(A.aQ(q))
s=r.c
if(s==null){r.d=null
return!1}else{r.d=s.b
r.c=s.c
return!0}},
$iK:1}
A.hf.prototype={
$1(a){return this.a(a)},
$S:41}
A.hg.prototype={
$2(a,b){return this.a(a,b)},
$S:33}
A.hh.prototype={
$1(a){return this.a(A.A(a))},
$S:43}
A.aH.prototype={
i(a){return this.bq(!1)},
bq(a){var s,r,q,p,o,n=this.co(),m=this.bg(),l=(a?"Record ":"")+"("
for(s=n.length,r="",q=0;q<s;++q,r=", "){l+=r
p=n[q]
if(typeof p=="string")l=l+p+": "
if(!(q<m.length))return A.b(m,q)
o=m[q]
l=a?l+A.iT(o):l+A.n(o)}l+=")"
return l.charCodeAt(0)==0?l:l},
co(){var s,r=this.$s
while($.fC.length<=r)B.b.t($.fC,null)
s=$.fC[r]
if(s==null){s=this.ci()
B.b.A($.fC,r,s)}return s},
ci(){var s,r,q,p=this.$r,o=p.indexOf("("),n=p.substring(1,o),m=p.substring(o),l=m==="()"?0:m.replace(/[^,]/g,"").length+1,k=A.x(new Array(l),t.f)
for(s=0;s<l;++s)k[s]=s
if(n!==""){r=n.split(",")
s=r.length
for(q=l;s>0;){--q;--s
B.b.A(k,q,r[s])}}return A.db(k,t.K)}}
A.b0.prototype={
bg(){return[this.a,this.b]},
I(a,b){if(b==null)return!1
return b instanceof A.b0&&this.$s===b.$s&&J.ab(this.a,b.a)&&J.ab(this.b,b.b)},
gu(a){return A.eG(this.$s,this.a,this.b,B.f)}}
A.d7.prototype={
i(a){return"RegExp/"+this.a+"/"+this.b.flags},
a3(a){var s=this.b.exec(a)
if(s==null)return null
return new A.fA(s)},
$ieI:1,
$il4:1}
A.fA.prototype={
ga8(){var s=this.b
return s.index+s[0].length}}
A.fk.prototype={
K(){var s=this.b
if(s===this)throw A.d(A.iI(this.a))
return s}}
A.aU.prototype={
gF(a){return B.aq},
bu(a,b,c){A.cH(a,b,c)
return c==null?new Uint8Array(a,b):new Uint8Array(a,b,c)},
cB(a,b,c){var s
A.cH(a,b,c)
s=new DataView(a,b)
return s},
bt(a){return this.cB(a,0,null)},
$io:1,
$iaU:1}
A.by.prototype={$iby:1}
A.c9.prototype={
gaP(a){if(((a.$flags|0)&2)!==0)return new A.fJ(a.buffer)
else return a.buffer},
cr(a,b,c,d){var s=A.P(b,0,c,d,null)
throw A.d(s)},
bc(a,b,c,d){if(b>>>0!==b||b>c)this.cr(a,b,c,d)}}
A.fJ.prototype={
bu(a,b,c){var s=A.ar(this.a,b,c)
s.$flags=3
return s},
bt(a){var s=A.iO(this.a,0,null)
s.$flags=3
return s}}
A.c7.prototype={
gF(a){return B.ar},
$io:1,
$iir:1}
A.L.prototype={
gk(a){return a.length},
cw(a,b,c,d,e){var s,r,q=a.length
this.bc(a,b,q,"start")
this.bc(a,c,q,"end")
if(b>c)throw A.d(A.P(b,0,c,null,null))
s=c-b
if(e<0)throw A.d(A.J(e,null))
r=d.length
if(r-e<s)throw A.d(A.at("Not enough elements"))
if(e!==0||r!==s)d=d.subarray(e,e+s)
a.set(d,b)},
$ia4:1}
A.c8.prototype={
j(a,b){A.aL(b,a,a.length)
return a[b]},
A(a,b,c){A.Q(c)
a.$flags&2&&A.l(a)
A.aL(b,a,a.length)
a[b]=c},
L(a,b,c,d,e){t.bM.a(d)
a.$flags&2&&A.l(a,5)
this.b9(a,b,c,d,e)},
T(a,b,c,d){return this.L(a,b,c,d,0)},
$ii:1,
$if:1,
$ij:1}
A.a6.prototype={
A(a,b,c){A.c(c)
a.$flags&2&&A.l(a)
A.aL(b,a,a.length)
a[b]=c},
L(a,b,c,d,e){t.Y.a(d)
a.$flags&2&&A.l(a,5)
if(t.eB.b(d)){this.cw(a,b,c,d,e)
return}this.b9(a,b,c,d,e)},
T(a,b,c,d){return this.L(a,b,c,d,0)},
$ii:1,
$if:1,
$ij:1}
A.dc.prototype={
gF(a){return B.as},
$io:1,
$iy:1}
A.dd.prototype={
gF(a){return B.at},
$io:1,
$iy:1}
A.de.prototype={
gF(a){return B.au},
j(a,b){A.aL(b,a,a.length)
return a[b]},
$io:1,
$iy:1}
A.df.prototype={
gF(a){return B.av},
j(a,b){A.aL(b,a,a.length)
return a[b]},
$io:1,
$iy:1}
A.dg.prototype={
gF(a){return B.aw},
j(a,b){A.aL(b,a,a.length)
return a[b]},
$io:1,
$iy:1}
A.dh.prototype={
gF(a){return B.ay},
j(a,b){A.aL(b,a,a.length)
return a[b]},
$io:1,
$iy:1,
$ihM:1}
A.di.prototype={
gF(a){return B.az},
j(a,b){A.aL(b,a,a.length)
return a[b]},
$io:1,
$iy:1}
A.ca.prototype={
gF(a){return B.aA},
gk(a){return a.length},
j(a,b){A.aL(b,a,a.length)
return a[b]},
$io:1,
$iy:1}
A.bc.prototype={
gF(a){return B.aB},
gk(a){return a.length},
j(a,b){A.aL(b,a,a.length)
return a[b]},
$io:1,
$ibc:1,
$iy:1,
$if1:1}
A.cu.prototype={}
A.cv.prototype={}
A.cw.prototype={}
A.cx.prototype={}
A.al.prototype={
h(a){return A.cE(v.typeUniverse,this,a)},
E(a){return A.ji(v.typeUniverse,this,a)}}
A.dN.prototype={}
A.fH.prototype={
i(a){return A.Y(this.a,null)}}
A.dM.prototype={
i(a){return this.a}}
A.bG.prototype={$iaE:1}
A.fe.prototype={
$1(a){var s=this.a,r=s.a
s.a=null
r.$0()},
$S:13}
A.fd.prototype={
$1(a){var s,r
this.a.a=t.M.a(a)
s=this.b
r=this.c
s.firstChild?s.removeChild(r):s.appendChild(r)},
$S:37}
A.ff.prototype={
$0(){this.a.$0()},
$S:14}
A.fg.prototype={
$0(){this.a.$0()},
$S:14}
A.fF.prototype={
cb(a,b){if(self.setTimeout!=null)self.setTimeout(A.bN(new A.fG(this,b),0),a)
else throw A.d(A.aY("`setTimeout()` not found."))}}
A.fG.prototype={
$0(){this.b.$0()},
$S:0}
A.dF.prototype={
aQ(a){var s,r=this,q=r.$ti
q.h("1/?").a(a)
if(a==null)a=q.c.a(a)
if(!r.b)r.a.av(a)
else{s=r.a
if(q.h("ai<1>").b(a))s.bb(a)
else s.bd(a)}},
aR(a,b){var s=this.a
if(this.b)s.aD(new A.ad(a,b))
else s.aw(new A.ad(a,b))}}
A.fP.prototype={
$1(a){return this.a.$2(0,a)},
$S:6}
A.fQ.prototype={
$2(a,b){this.a.$2(1,new A.bY(a,t.l.a(b)))},
$S:45}
A.h7.prototype={
$2(a,b){this.a(A.c(a),b)},
$S:48}
A.ad.prototype={
i(a){return A.n(this.a)},
$iq:1,
ga0(){return this.b}}
A.dI.prototype={
aR(a,b){var s=this.a
if((s.a&30)!==0)throw A.d(A.at("Future already completed"))
s.aw(A.m7(a,b))},
bx(a){return this.aR(a,null)}}
A.cq.prototype={
aQ(a){var s,r=this.$ti
r.h("1/?").a(a)
s=this.a
if((s.a&30)!==0)throw A.d(A.at("Future already completed"))
s.av(r.h("1/").a(a))}}
A.bj.prototype={
dh(a){if((this.c&15)!==6)return!0
return this.b.b.b_(t.bO.a(this.d),a.a,t.v,t.K)},
d6(a){var s,r=this,q=r.e,p=null,o=t.z,n=t.K,m=a.a,l=r.b.b
if(t.R.b(q))p=l.dn(q,m,a.b,o,n,t.l)
else p=l.b_(t.x.a(q),m,o,n)
try{o=r.$ti.h("2/").a(p)
return o}catch(s){if(t.eK.b(A.I(s))){if((r.c&1)!==0)throw A.d(A.J("The error handler of Future.then must return a value of the returned future's type","onError"))
throw A.d(A.J("The error handler of Future.catchError must return a value of the future's type","onError"))}else throw s}}}
A.F.prototype={
b0(a,b,c){var s,r,q,p=this.$ti
p.E(c).h("1/(2)").a(a)
s=$.w
if(s===B.d){if(b!=null&&!t.R.b(b)&&!t.x.b(b))throw A.d(A.ax(b,"onError",u.c))}else{c.h("@<0/>").E(p.c).h("1(2)").a(a)
if(b!=null)b=A.mo(b,s)}r=new A.F(s,c.h("F<0>"))
q=b==null?1:3
this.au(new A.bj(r,q,a,b,p.h("@<1>").E(c).h("bj<1,2>")))
return r},
ds(a,b){return this.b0(a,null,b)},
bp(a,b,c){var s,r=this.$ti
r.E(c).h("1/(2)").a(a)
s=new A.F($.w,c.h("F<0>"))
this.au(new A.bj(s,19,a,b,r.h("@<1>").E(c).h("bj<1,2>")))
return s},
cv(a){this.a=this.a&1|16
this.c=a},
af(a){this.a=a.a&30|this.a&1
this.c=a.c},
au(a){var s,r=this,q=r.a
if(q<=3){a.a=t.F.a(r.c)
r.c=a}else{if((q&4)!==0){s=t.d.a(r.c)
if((s.a&24)===0){s.au(a)
return}r.af(s)}A.e1(null,null,r.b,t.M.a(new A.fp(r,a)))}},
bh(a){var s,r,q,p,o,n,m=this,l={}
l.a=a
if(a==null)return
s=m.a
if(s<=3){r=t.F.a(m.c)
m.c=a
if(r!=null){q=a.a
for(p=a;q!=null;p=q,q=o)o=q.a
p.a=r}}else{if((s&4)!==0){n=t.d.a(m.c)
if((n.a&24)===0){n.bh(a)
return}m.af(n)}l.a=m.ah(a)
A.e1(null,null,m.b,t.M.a(new A.ft(l,m)))}},
ag(){var s=t.F.a(this.c)
this.c=null
return this.ah(s)},
ah(a){var s,r,q
for(s=a,r=null;s!=null;r=s,s=q){q=s.a
s.a=r}return r},
bd(a){var s,r=this
r.$ti.c.a(a)
s=r.ag()
r.a=8
r.c=a
A.bE(r,s)},
cg(a){var s,r,q=this
if((a.a&16)!==0){s=q.b===a.b
s=!(s||s)}else s=!1
if(s)return
r=q.ag()
q.af(a)
A.bE(q,r)},
aD(a){var s=this.ag()
this.cv(a)
A.bE(this,s)},
av(a){var s=this.$ti
s.h("1/").a(a)
if(s.h("ai<1>").b(a)){this.bb(a)
return}this.cc(a)},
cc(a){var s=this
s.$ti.c.a(a)
s.a^=2
A.e1(null,null,s.b,t.M.a(new A.fr(s,a)))},
bb(a){A.hV(this.$ti.h("ai<1>").a(a),this,!1)
return},
aw(a){this.a^=2
A.e1(null,null,this.b,t.M.a(new A.fq(this,a)))},
$iai:1}
A.fp.prototype={
$0(){A.bE(this.a,this.b)},
$S:0}
A.ft.prototype={
$0(){A.bE(this.b,this.a.a)},
$S:0}
A.fs.prototype={
$0(){A.hV(this.a.a,this.b,!0)},
$S:0}
A.fr.prototype={
$0(){this.a.bd(this.b)},
$S:0}
A.fq.prototype={
$0(){this.a.aD(this.b)},
$S:0}
A.fw.prototype={
$0(){var s,r,q,p,o,n,m,l,k=this,j=null
try{q=k.a.a
j=q.b.b.dm(t.fO.a(q.d),t.z)}catch(p){s=A.I(p)
r=A.bp(p)
if(k.c&&t.n.a(k.b.a.c).a===s){q=k.a
q.c=t.n.a(k.b.a.c)}else{q=s
o=r
if(o==null)o=A.hx(q)
n=k.a
n.c=new A.ad(q,o)
q=n}q.b=!0
return}if(j instanceof A.F&&(j.a&24)!==0){if((j.a&16)!==0){q=k.a
q.c=t.n.a(j.c)
q.b=!0}return}if(j instanceof A.F){m=k.b.a
l=new A.F(m.b,m.$ti)
j.b0(new A.fx(l,m),new A.fy(l),t.H)
q=k.a
q.c=l
q.b=!1}},
$S:0}
A.fx.prototype={
$1(a){this.a.cg(this.b)},
$S:13}
A.fy.prototype={
$2(a,b){A.bl(a)
t.l.a(b)
this.a.aD(new A.ad(a,b))},
$S:60}
A.fv.prototype={
$0(){var s,r,q,p,o,n,m,l
try{q=this.a
p=q.a
o=p.$ti
n=o.c
m=n.a(this.b)
q.c=p.b.b.b_(o.h("2/(1)").a(p.d),m,o.h("2/"),n)}catch(l){s=A.I(l)
r=A.bp(l)
q=s
p=r
if(p==null)p=A.hx(q)
o=this.a
o.c=new A.ad(q,p)
o.b=!0}},
$S:0}
A.fu.prototype={
$0(){var s,r,q,p,o,n,m,l=this
try{s=t.n.a(l.a.a.c)
p=l.b
if(p.a.dh(s)&&p.a.e!=null){p.c=p.a.d6(s)
p.b=!1}}catch(o){r=A.I(o)
q=A.bp(o)
p=t.n.a(l.a.a.c)
if(p.a===r){n=l.b
n.c=p
p=n}else{p=r
n=q
if(n==null)n=A.hx(p)
m=l.b
m.c=new A.ad(p,n)
p=m}p.b=!0}},
$S:0}
A.dG.prototype={}
A.dZ.prototype={}
A.cG.prototype={$ij0:1}
A.dV.prototype={
dq(a){var s,r,q
t.M.a(a)
try{if(B.d===$.w){a.$0()
return}A.jy(null,null,this,a,t.H)}catch(q){s=A.I(q)
r=A.bp(q)
A.h5(A.bl(s),t.l.a(r))}},
dr(a,b,c){var s,r,q
c.h("~(0)").a(a)
c.a(b)
try{if(B.d===$.w){a.$1(b)
return}A.jz(null,null,this,a,b,t.H,c)}catch(q){s=A.I(q)
r=A.bp(q)
A.h5(A.bl(s),t.l.a(r))}},
cC(a){return new A.fD(this,t.M.a(a))},
cD(a,b){return new A.fE(this,b.h("~(0)").a(a),b)},
dm(a,b){b.h("0()").a(a)
if($.w===B.d)return a.$0()
return A.jy(null,null,this,a,b)},
b_(a,b,c,d){c.h("@<0>").E(d).h("1(2)").a(a)
d.a(b)
if($.w===B.d)return a.$1(b)
return A.jz(null,null,this,a,b,c,d)},
dn(a,b,c,d,e,f){d.h("@<0>").E(e).E(f).h("1(2,3)").a(a)
e.a(b)
f.a(c)
if($.w===B.d)return a.$2(b,c)
return A.mq(null,null,this,a,b,c,d,e,f)},
bM(a,b,c,d){return b.h("@<0>").E(c).E(d).h("1(2,3)").a(a)}}
A.fD.prototype={
$0(){return this.a.dq(this.b)},
$S:0}
A.fE.prototype={
$1(a){var s=this.c
return this.a.dr(this.b,s.a(a),s)},
$S(){return this.c.h("~(0)")}}
A.h6.prototype={
$0(){A.kD(this.a,this.b)},
$S:0}
A.k.prototype={
gG(a){return new A.b9(a,this.gk(a),A.aw(a).h("b9<k.E>"))},
H(a,b){return this.j(a,b)},
ga_(a){if(this.gk(a)===0)throw A.d(A.ex())
if(this.gk(a)>1)throw A.d(A.iE())
return this.j(a,0)},
ak(a,b,c){var s=A.aw(a)
return new A.a5(a,s.E(c).h("1(k.E)").a(b),s.h("@<k.E>").E(c).h("a5<1,2>"))},
aq(a,b){return A.iX(a,b,null,A.aw(a).h("k.E"))},
bE(a,b,c,d){var s
A.aw(a).h("k.E?").a(d)
A.dp(b,c,this.gk(a))
for(s=b;s<c;++s)this.A(a,s,d)},
L(a,b,c,d,e){var s,r,q,p,o
A.aw(a).h("f<k.E>").a(d)
A.dp(b,c,this.gk(a))
s=c-b
if(s===0)return
A.bA(e,"skipCount")
if(t.b.b(d)){r=e
q=d}else{q=J.kp(d,e).bQ(0,!1)
r=0}p=J.cL(q)
if(r+s>p.gk(q))throw A.d(A.kL())
if(r<b)for(o=s-1;o>=0;--o)this.A(a,b+o,p.j(q,r+o))
else for(o=0;o<s;++o)this.A(a,b+o,p.j(q,r+o))},
T(a,b,c,d){return this.L(a,b,c,d,0)},
b3(a,b,c){A.aw(a).h("f<k.E>").a(c)
this.T(a,b,b+c.length,c)},
i(a){return A.iF(a,"[","]")},
$ii:1,
$if:1,
$ij:1}
A.a_.prototype={
aU(a,b){var s,r,q,p=A.S(this)
p.h("~(a_.K,a_.V)").a(b)
for(s=J.cN(this.gaZ()),p=p.h("a_.V");s.p();){r=s.gv()
q=this.j(0,r)
b.$2(r,q==null?p.a(q):q)}},
gk(a){return J.ac(this.gaZ())},
i(a){return A.hI(this)},
$iba:1}
A.eD.prototype={
$2(a,b){var s,r=this.a
if(!r.a)this.b.a+=", "
r.a=!1
r=this.b
s=A.n(a)
r.a=(r.a+=s)+": "
s=A.n(b)
r.a+=s},
$S:22}
A.fL.prototype={
$0(){var s,r
try{s=new TextDecoder("utf-8",{fatal:true})
return s}catch(r){}return null},
$S:11}
A.fK.prototype={
$0(){var s,r
try{s=new TextDecoder("utf-8",{fatal:false})
return s}catch(r){}return null},
$S:11}
A.bS.prototype={}
A.cW.prototype={}
A.d_.prototype={}
A.dy.prototype={
bB(a){t.L.a(a)
return new A.cF(!1).aE(a,0,null,!0)}}
A.f2.prototype={
P(a){var s,r,q,p,o=a.length,n=A.dp(0,null,o)
if(n===0)return new Uint8Array(0)
s=n*3
r=new Uint8Array(s)
q=new A.fM(r)
if(q.cp(a,0,n)!==n){p=n-1
if(!(p>=0&&p<o))return A.b(a,p)
q.aO()}return new Uint8Array(r.subarray(0,A.lX(0,q.b,s)))}}
A.fM.prototype={
aO(){var s,r=this,q=r.c,p=r.b,o=r.b=p+1
q.$flags&2&&A.l(q)
s=q.length
if(!(p<s))return A.b(q,p)
q[p]=239
p=r.b=o+1
if(!(o<s))return A.b(q,o)
q[o]=191
r.b=p+1
if(!(p<s))return A.b(q,p)
q[p]=189},
cA(a,b){var s,r,q,p,o,n=this
if((b&64512)===56320){s=65536+((a&1023)<<10)|b&1023
r=n.c
q=n.b
p=n.b=q+1
r.$flags&2&&A.l(r)
o=r.length
if(!(q<o))return A.b(r,q)
r[q]=s>>>18|240
q=n.b=p+1
if(!(p<o))return A.b(r,p)
r[p]=s>>>12&63|128
p=n.b=q+1
if(!(q<o))return A.b(r,q)
r[q]=s>>>6&63|128
n.b=p+1
if(!(p<o))return A.b(r,p)
r[p]=s&63|128
return!0}else{n.aO()
return!1}},
cp(a,b,c){var s,r,q,p,o,n,m,l,k=this
if(b!==c){s=c-1
if(!(s>=0&&s<a.length))return A.b(a,s)
s=(a.charCodeAt(s)&64512)===55296}else s=!1
if(s)--c
for(s=k.c,r=s.$flags|0,q=s.length,p=a.length,o=b;o<c;++o){if(!(o<p))return A.b(a,o)
n=a.charCodeAt(o)
if(n<=127){m=k.b
if(m>=q)break
k.b=m+1
r&2&&A.l(s)
s[m]=n}else{m=n&64512
if(m===55296){if(k.b+4>q)break
m=o+1
if(!(m<p))return A.b(a,m)
if(k.cA(n,a.charCodeAt(m)))o=m}else if(m===56320){if(k.b+3>q)break
k.aO()}else if(n<=2047){m=k.b
l=m+1
if(l>=q)break
k.b=l
r&2&&A.l(s)
if(!(m<q))return A.b(s,m)
s[m]=n>>>6|192
k.b=l+1
s[l]=n&63|128}else{m=k.b
if(m+2>=q)break
l=k.b=m+1
r&2&&A.l(s)
if(!(m<q))return A.b(s,m)
s[m]=n>>>12|224
m=k.b=l+1
if(!(l<q))return A.b(s,l)
s[l]=n>>>6&63|128
k.b=m+1
if(!(m<q))return A.b(s,m)
s[m]=n&63|128}}}return o}}
A.cF.prototype={
aE(a,b,c,d){var s,r,q,p,o,n,m,l=this
t.L.a(a)
s=A.dp(b,c,a.length)
if(b===s)return""
if(a instanceof Uint8Array){r=a
q=r
p=0}else{q=A.lK(a,b,s)
s-=b
p=b
b=0}if(s-b>=15){o=l.a
n=A.lJ(o,q,b,s)
if(n!=null){if(!o)return n
if(n.indexOf("\ufffd")<0)return n}}n=l.aF(q,b,s,!0)
o=l.b
if((o&1)!==0){m=A.lL(o)
l.b=0
throw A.d(A.ev(m,a,p+l.c))}return n},
aF(a,b,c,d){var s,r,q=this
if(c-b>1000){s=B.a.l(b+c,2)
r=q.aF(a,b,s,!1)
if((q.b&1)!==0)return r
return r+q.aF(a,s,c,d)}return q.cG(a,b,c,d)},
cG(a,b,a0,a1){var s,r,q,p,o,n,m,l,k=this,j="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFFFFFFFFFFFFFFFFGGGGGGGGGGGGGGGGHHHHHHHHHHHHHHHHHHHHHHHHHHHIHHHJEEBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBKCCCCCCCCCCCCDCLONNNMEEEEEEEEEEE",i=" \x000:XECCCCCN:lDb \x000:XECCCCCNvlDb \x000:XECCCCCN:lDb AAAAA\x00\x00\x00\x00\x00AAAAA00000AAAAA:::::AAAAAGG000AAAAA00KKKAAAAAG::::AAAAA:IIIIAAAAA000\x800AAAAA\x00\x00\x00\x00 AAAAA",h=65533,g=k.b,f=k.c,e=new A.cm(""),d=b+1,c=a.length
if(!(b>=0&&b<c))return A.b(a,b)
s=a[b]
A:for(r=k.a;;){for(;;d=o){if(!(s>=0&&s<256))return A.b(j,s)
q=j.charCodeAt(s)&31
f=g<=32?s&61694>>>q:(s&63|f<<6)>>>0
p=g+q
if(!(p>=0&&p<144))return A.b(i,p)
g=i.charCodeAt(p)
if(g===0){p=A.bz(f)
e.a+=p
if(d===a0)break A
break}else if((g&1)!==0){if(r)switch(g){case 69:case 67:p=A.bz(h)
e.a+=p
break
case 65:p=A.bz(h)
e.a+=p;--d
break
default:p=A.bz(h)
e.a=(e.a+=p)+p
break}else{k.b=g
k.c=d-1
return""}g=0}if(d===a0)break A
o=d+1
if(!(d>=0&&d<c))return A.b(a,d)
s=a[d]}o=d+1
if(!(d>=0&&d<c))return A.b(a,d)
s=a[d]
if(s<128){for(;;){if(!(o<a0)){n=a0
break}m=o+1
if(!(o>=0&&o<c))return A.b(a,o)
s=a[o]
if(s>=128){n=m-1
o=m
break}o=m}if(n-d<20)for(l=d;l<n;++l){if(!(l<c))return A.b(a,l)
p=A.bz(a[l])
e.a+=p}else{p=A.la(a,d,n)
e.a+=p}if(n===a0)break A
d=o}else d=o}if(a1&&g>32)if(r){c=A.bz(h)
e.a+=c}else{k.b=77
k.c=a0
return""}k.b=g
k.c=f
c=e.a
return c.charCodeAt(0)==0?c:c}}
A.z.prototype={
D(a){var s,r,q=this,p=q.c
if(p===0)return q
s=!q.a
r=q.b
p=A.a1(p,r)
return new A.z(p===0?!1:s,r,p)},
ck(a){var s,r,q,p,o,n,m,l=this.c
if(l===0)return $.E()
s=l+a
r=this.b
q=new Uint16Array(s)
for(p=l-1,o=r.length;p>=0;--p){n=p+a
if(!(p<o))return A.b(r,p)
m=r[p]
if(!(n>=0&&n<s))return A.b(q,n)
q[n]=m}o=this.a
n=A.a1(s,q)
return new A.z(n===0?!1:o,q,n)},
cl(a){var s,r,q,p,o,n,m,l,k=this,j=k.c
if(j===0)return $.E()
s=j-a
if(s<=0)return k.a?$.ig():$.E()
r=k.b
q=new Uint16Array(s)
for(p=r.length,o=a;o<j;++o){n=o-a
if(!(o>=0&&o<p))return A.b(r,o)
m=r[o]
if(!(n<s))return A.b(q,n)
q[n]=m}n=k.a
m=A.a1(s,q)
l=new A.z(m===0?!1:n,q,m)
if(n)for(o=0;o<a;++o){if(!(o<p))return A.b(r,o)
if(r[o]!==0)return l.ac(0,$.Z())}return l},
O(a,b){var s,r,q,p,o,n=this
if(b<0)throw A.d(A.J("shift-amount must be posititve "+b,null))
s=n.c
if(s===0)return n
r=B.a.l(b,16)
if(B.a.n(b,16)===0)return n.ck(r)
q=s+r+1
p=new Uint16Array(q)
A.j7(n.b,s,b,p)
s=n.a
o=A.a1(q,p)
return new A.z(o===0?!1:s,p,o)},
Z(a,b){var s,r,q,p,o,n,m,l,k,j=this
if(b<0)throw A.d(A.J("shift-amount must be posititve "+b,null))
s=j.c
if(s===0)return j
r=B.a.l(b,16)
q=B.a.n(b,16)
if(q===0)return j.cl(r)
p=s-r
if(p<=0)return j.a?$.ig():$.E()
o=j.b
n=new Uint16Array(p)
A.lo(o,s,b,n)
s=j.a
m=A.a1(p,n)
l=new A.z(m===0?!1:s,n,m)
if(s){s=o.length
if(!(r>=0&&r<s))return A.b(o,r)
if((o[r]&B.a.O(1,q)-1)>>>0!==0)return l.ac(0,$.Z())
for(k=0;k<r;++k){if(!(k<s))return A.b(o,k)
if(o[k]!==0)return l.ac(0,$.Z())}}return l},
m(a,b){var s,r
t.cl.a(b)
s=this.a
if(s===b.a){r=A.fh(this.b,this.c,b.b,b.c)
return s?0-r:r}return s?-1:1},
ar(a,b){var s,r,q,p=this,o=p.c,n=a.c
if(o<n)return a.ar(p,b)
if(o===0)return $.E()
if(n===0)return p.a===b?p:p.D(0)
s=o+1
r=new Uint16Array(s)
A.lk(p.b,o,a.b,n,r)
q=A.a1(s,r)
return new A.z(q===0?!1:b,r,q)},
ae(a,b){var s,r,q,p=this,o=p.c
if(o===0)return $.E()
s=a.c
if(s===0)return p.a===b?p:p.D(0)
r=new Uint16Array(o)
A.dH(p.b,o,a.b,s,r)
q=A.a1(o,r)
return new A.z(q===0?!1:b,r,q)},
S(a,b){var s,r,q=this,p=q.c
if(p===0)return b
s=b.c
if(s===0)return q
r=q.a
if(r===b.a)return q.ar(b,r)
if(A.fh(q.b,p,b.b,s)>=0)return q.ae(b,r)
return b.ae(q,!r)},
ac(a,b){var s,r,q=this,p=q.c
if(p===0)return b.D(0)
s=b.c
if(s===0)return q
r=q.a
if(r!==b.a)return q.ar(b,r)
if(A.fh(q.b,p,b.b,s)>=0)return q.ae(b,r)
return b.ae(q,!r)},
q(a,b){var s,r,q,p,o,n,m,l=this.c,k=b.c
if(l===0||k===0)return $.E()
s=l+k
r=this.b
q=b.b
p=new Uint16Array(s)
for(o=q.length,n=0;n<k;){if(!(n<o))return A.b(q,n)
A.j8(q[n],r,0,p,n,l);++n}o=this.a!==b.a
m=A.a1(s,p)
return new A.z(m===0?!1:o,p,m)},
be(a){var s,r,q,p
if(this.c<a.c)return $.E()
this.bf(a)
s=$.hQ.K()-$.cs.K()
r=A.hS($.hP.K(),$.cs.K(),$.hQ.K(),s)
q=A.a1(s,r)
p=new A.z(!1,r,q)
return this.a!==a.a&&q>0?p.D(0):p},
bk(a){var s,r,q,p=this
if(p.c<a.c)return p
p.bf(a)
s=A.hS($.hP.K(),0,$.cs.K(),$.cs.K())
r=A.a1($.cs.K(),s)
q=new A.z(!1,s,r)
if($.hR.K()>0)q=q.Z(0,$.hR.K())
return p.a&&q.c>0?q.D(0):q},
bf(a){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c=this,b=c.c
if(b===$.j4&&a.c===$.j6&&c.b===$.j3&&a.b===$.j5)return
s=a.b
r=a.c
q=r-1
if(!(q>=0&&q<s.length))return A.b(s,q)
p=16-B.a.gbw(s[q])
if(p>0){o=new Uint16Array(r+5)
n=A.j2(s,r,p,o)
m=new Uint16Array(b+5)
l=A.j2(c.b,b,p,m)}else{m=A.hS(c.b,0,b,b+2)
n=r
o=s
l=b}q=n-1
if(!(q>=0&&q<o.length))return A.b(o,q)
k=o[q]
j=l-n
i=new Uint16Array(l)
h=A.hT(o,n,j,i)
g=l+1
q=m.$flags|0
if(A.fh(m,l,i,h)>=0){q&2&&A.l(m)
if(!(l>=0&&l<m.length))return A.b(m,l)
m[l]=1
A.dH(m,g,i,h,m)}else{q&2&&A.l(m)
if(!(l>=0&&l<m.length))return A.b(m,l)
m[l]=0}q=n+2
f=new Uint16Array(q)
if(!(n>=0&&n<q))return A.b(f,n)
f[n]=1
A.dH(f,n+1,o,n,f)
e=l-1
for(q=m.length;j>0;){d=A.ll(k,m,e);--j
A.j8(d,f,0,m,j,n)
if(!(e>=0&&e<q))return A.b(m,e)
if(m[e]<d){h=A.hT(f,n,j,i)
A.dH(m,g,i,h,m)
while(--d,m[e]<d)A.dH(m,g,i,h,m)}--e}$.j3=c.b
$.j4=b
$.j5=s
$.j6=r
$.hP.b=m
$.hQ.b=g
$.cs.b=n
$.hR.b=p},
gu(a){var s,r,q,p,o=new A.fi(),n=this.c
if(n===0)return 6707
s=this.a?83585:429689
for(r=this.b,q=r.length,p=0;p<n;++p){if(!(p<q))return A.b(r,p)
s=o.$2(s,r[p])}return new A.fj().$1(s)},
I(a,b){if(b==null)return!1
return b instanceof A.z&&this.m(0,b)===0},
ad(a,b){if(b.c===0)throw A.d(B.m)
return this.be(b)},
dl(a,b){if(b.c===0)throw A.d(B.m)
return this.bk(b)},
gU(a){if(this.c===0)return 0
return this.a?-1:1},
J(a){var s,r
if(a<0)throw A.d(A.J("Exponent must not be negative: "+a,null))
if(a===0)return $.Z()
s=$.Z()
for(r=this;a!==0;){if((a&1)===1)s=s.q(0,r)
a=B.a.B(a,1)
if(a!==0)r=r.q(0,r)}return s},
i(a){var s,r,q,p,o,n=this,m=n.c
if(m===0)return"0"
if(m===1){if(n.a){m=n.b
if(0>=m.length)return A.b(m,0)
return B.a.i(-m[0])}m=n.b
if(0>=m.length)return A.b(m,0)
return B.a.i(m[0])}s=A.x([],t.s)
m=n.a
r=m?n.D(0):n
while(r.c>1){q=$.ie()
if(q.c===0)A.u(B.m)
p=r.bk(q).i(0)
B.b.t(s,p)
o=p.length
if(o===1)B.b.t(s,"000")
if(o===2)B.b.t(s,"00")
if(o===3)B.b.t(s,"0")
r=r.be(q)}q=r.b
if(0>=q.length)return A.b(q,0)
B.b.t(s,B.a.i(q[0]))
if(m)B.b.t(s,"-")
return new A.ce(s,t.bJ).d9(0)},
$ie4:1,
$it:1}
A.fi.prototype={
$2(a,b){a=a+b&536870911
a=a+((a&524287)<<10)&536870911
return a^a>>>6},
$S:26}
A.fj.prototype={
$1(a){a=a+((a&67108863)<<3)&536870911
a^=a>>>11
return a+((a&16383)<<15)&536870911},
$S:28}
A.ct.prototype={
bv(a,b,c){var s
this.$ti.c.a(b)
s=this.a
if(s!=null)s.register(a,b,c)},
bC(a){var s=this.a
if(s!=null)s.unregister(a)},
$ikE:1}
A.eu.prototype={
$0(){var s=this
return A.u(A.J("("+s.a+", "+s.b+", "+s.c+", "+s.d+", "+s.e+", "+s.f+", "+s.r+", "+s.w+")",null))},
$S:29}
A.a3.prototype={
I(a,b){if(b==null)return!1
return b instanceof A.a3&&this.a===b.a&&this.b===b.b&&this.c===b.c},
gu(a){return A.eG(this.a,this.b,B.f,B.f)},
m(a,b){var s
t.k.a(b)
s=B.a.m(this.a,b.a)
if(s!==0)return s
return B.a.m(this.b,b.b)},
dt(){var s=this
if(s.c)return s
return new A.a3(s.a,s.b,!0)},
i(a){var s=this,r=A.kA(A.eO(s)),q=A.cZ(A.eM(s)),p=A.cZ(A.eJ(s)),o=A.cZ(A.eK(s)),n=A.cZ(A.eL(s)),m=A.cZ(A.eN(s)),l=A.iu(A.hJ(s)),k=s.b,j=k===0?"":A.iu(k)
k=r+"-"+q
if(s.c)return k+"-"+p+" "+o+":"+n+":"+m+"."+l+j+"Z"
else return k+"-"+p+" "+o+":"+n+":"+m+"."+l+j},
$it:1}
A.aR.prototype={
I(a,b){if(b==null)return!1
return b instanceof A.aR&&this.a===b.a},
gu(a){return B.a.gu(this.a)},
m(a,b){return B.a.m(this.a,t.J.a(b).a)},
i(a){var s,r,q,p,o,n=this.a,m=B.a.l(n,36e8),l=n%36e8
if(n<0){m=0-m
n=0-l
s="-"}else{n=l
s=""}r=B.a.l(n,6e7)
n%=6e7
q=r<10?"0":""
p=B.a.l(n,1e6)
o=p<10?"0":""
return s+m+":"+q+r+":"+o+p+"."+B.c.R(B.a.i(n%1e6),6,"0")},
$it:1}
A.fm.prototype={
i(a){return this.aH()}}
A.q.prototype={
ga0(){return A.kW(this)}}
A.cO.prototype={
i(a){var s=this.a
if(s!=null)return"Assertion failed: "+A.bX(s)
return"Assertion failed"}}
A.aE.prototype={}
A.ah.prototype={
gaJ(){return"Invalid argument"+(!this.a?"(s)":"")},
gaI(){return""},
i(a){var s=this,r=s.c,q=r==null?"":" ("+r+")",p=s.d,o=p==null?"":": "+A.n(p),n=s.gaJ()+q+o
if(!s.a)return n
return n+s.gaI()+": "+A.bX(s.gaX())},
gaX(){return this.b}}
A.aC.prototype={
gaX(){return A.jo(this.b)},
gaJ(){return"RangeError"},
gaI(){var s,r=this.e,q=this.f
if(r==null)s=q!=null?": Not less than or equal to "+A.n(q):""
else if(q==null)s=": Not greater than or equal to "+A.n(r)
else if(q>r)s=": Not in inclusive range "+A.n(r)+".."+A.n(q)
else s=q<r?": Valid value range is empty":": Only valid value is "+A.n(r)
return s}}
A.bZ.prototype={
gaX(){return A.c(this.b)},
gaJ(){return"RangeError"},
gaI(){if(A.c(this.b)<0)return": index must not be negative"
var s=this.f
if(s===0)return": no indices are valid"
return": index should be less than "+s},
$iaC:1,
gk(a){return this.f}}
A.co.prototype={
i(a){return"Unsupported operation: "+this.a}}
A.dv.prototype={
i(a){return"UnimplementedError: "+this.a}}
A.be.prototype={
i(a){return"Bad state: "+this.a}}
A.cV.prototype={
i(a){var s=this.a
if(s==null)return"Concurrent modification during iteration."
return"Concurrent modification during iteration: "+A.bX(s)+"."}}
A.dk.prototype={
i(a){return"Out of Memory"},
ga0(){return null},
$iq:1}
A.cl.prototype={
i(a){return"Stack Overflow"},
ga0(){return null},
$iq:1}
A.fn.prototype={
i(a){return"Exception: "+this.a}}
A.v.prototype={
i(a){var s,r,q,p,o,n,m,l,k,j,i,h=this.a,g=""!==h?"FormatException: "+h:"FormatException",f=this.c,e=this.b
if(typeof e=="string"){if(f!=null)s=f<0||f>e.length
else s=!1
if(s)f=null
if(f==null){if(e.length>78)e=B.c.a1(e,0,75)+"..."
return g+"\n"+e}for(r=e.length,q=1,p=0,o=!1,n=0;n<f;++n){if(!(n<r))return A.b(e,n)
m=e.charCodeAt(n)
if(m===10){if(p!==n||!o)++q
p=n+1
o=!1}else if(m===13){++q
p=n+1
o=!0}}g=q>1?g+(" (at line "+q+", character "+(f-p+1)+")\n"):g+(" (at character "+(f+1)+")\n")
for(n=f;n<r;++n){if(!(n>=0))return A.b(e,n)
m=e.charCodeAt(n)
if(m===10||m===13){r=n
break}}l=""
if(r-p>78){k="..."
if(f-p<75){j=p+75
i=p}else{if(r-f<75){i=r-75
j=r
k=""}else{i=f-36
j=f+36}l="..."}}else{j=r
i=p
k=""}return g+l+B.c.a1(e,i,j)+k+"\n"+B.c.q(" ",f-i+l.length)+"^\n"}else return f!=null?g+(" (at offset "+A.n(f)+")"):g}}
A.d2.prototype={
ga0(){return null},
i(a){return"IntegerDivisionByZeroException"},
$iq:1}
A.f.prototype={
ak(a,b,c){var s=A.S(this)
return A.kU(this,s.E(c).h("1(f.E)").a(b),s.h("f.E"),c)},
bQ(a,b){var s=A.da(this,A.S(this).h("f.E"))
s.$flags=1
return s},
gk(a){var s,r=this.gG(this)
for(s=0;r.p();)++s
return s},
aq(a,b){return A.l6(this,b,A.S(this).h("f.E"))},
H(a,b){var s,r
A.bA(b,"index")
s=this.gG(this)
for(r=b;s.p();){if(r===0)return s.gv();--r}throw A.d(A.ew(b,b-r,this,null,"index"))},
i(a){return A.kM(this,"(",")")}}
A.M.prototype={
gu(a){return A.e.prototype.gu.call(this,0)},
i(a){return"null"}}
A.e.prototype={$ie:1,
I(a,b){return this===b},
gu(a){return A.dm(this)},
i(a){return"Instance of '"+A.dn(this)+"'"},
gF(a){return A.mM(this)},
toString(){return this.i(this)}}
A.e_.prototype={
i(a){return""},
$iaW:1}
A.cm.prototype={
gk(a){return this.a.length},
i(a){var s=this.a
return s.charCodeAt(0)==0?s:s}}
A.d0.prototype={
i(a){return"Expando:null"}}
A.eE.prototype={
i(a){return"Promise was rejected with a value of `"+(this.a?"undefined":"null")+"`."}}
A.hl.prototype={
$1(a){return this.a.aQ(this.b.h("0/?").a(a))},
$S:6}
A.hm.prototype={
$1(a){if(a==null)return this.a.bx(new A.eE(a===undefined))
return this.a.bx(a)},
$S:6}
A.dQ.prototype={
ca(){var s=self.crypto
if(s!=null)if(s.getRandomValues!=null)return
throw A.d(A.aY("No source of cryptographically secure random numbers available."))},
bK(a){var s,r,q,p,o,n,m,l
if(a<=0||a>4294967296)throw A.d(A.aV("max must be in range 0 < max \u2264 2^32, was "+a))
if(a>255)if(a>65535)s=a>16777215?4:3
else s=2
else s=1
r=this.a
r.$flags&2&&A.l(r,11)
r.setUint32(0,0,!1)
q=4-s
p=A.c(Math.pow(256,s))
for(o=a-1,n=(a&o)===0;;){crypto.getRandomValues(J.ii(B.ae.gaP(r),q,s))
m=r.getUint32(0,!1)
if(n)return(m&o)>>>0
l=m%a
if(m-l+a<p)return l}},
$il_:1}
A.dj.prototype={}
A.dx.prototype={}
A.eV.prototype={}
A.cj.prototype={}
A.ho.prototype={
$1(a){var s
A.B(a)
s=this.a
s.a=s.a.ds(new A.hn(a,this.b,this.c),t.H)},
$S:30}
A.hn.prototype={
$1(a){var s=0,r=A.aM(t.H),q=1,p=[],o=this,n,m,l,k,j,i,h,g,f,e
var $async$$1=A.aN(function(b,c){if(b===1){p.push(c)
s=q}for(;;)switch(s){case 0:f=o.a.data
f.toString
n=t.c.a(f)
m=n[0]
q=3
f=o.b
i=n[1]
i.toString
s=6
return A.R(f.W(A.A(i),n[2]),$async$$1)
case 6:l=c
f=f.b
if(f==null)f=null
else{f=f.b
f=A.c(f.a.d.sqlite3_get_autocommit(f.b))===0}if(f==null)f=null
o.c.postMessage([m,!0,f,l])
q=1
s=5
break
case 3:q=2
e=p.pop()
k=A.I(e)
j=null
if(k instanceof A.ck)j=A.x(["sqlite",k.a,k.c&255,k.c],t.f)
else{g=k instanceof A.a0?k.a:"DRIVER.SQLITE"
j=A.x([g,J.b4(k)],t.s)}f=o.b.b
if(f==null)f=null
else{f=f.b
f=A.c(f.a.d.sqlite3_get_autocommit(f.b))===0}if(f==null)f=null
o.c.postMessage([m,!1,f,j])
s=5
break
case 2:s=1
break
case 5:return A.aJ(null,r)
case 1:return A.aI(p.at(-1),r)}})
return A.aK($async$$1,r)},
$S:31}
A.fO.prototype={
W(a6,a7){var s=0,r=A.aM(t.X),q,p=2,o=[],n=this,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5
var $async$W=A.aN(function(a8,a9){if(a8===1){o.push(a9)
s=p}for(;;)A:switch(s){case 0:if(a6==="hello"){q=A.x([1,"ce6071ece644ad5fffa944df626c410c890505dd8c287d52065c2ce8890a95b8"],t.f)
s=1
break}s=a6==="open"?3:4
break
case 3:if(n.a!=null)throw A.d(B.ag)
a7.toString
m=t.c.a(a7)
d=m[0]
d.toString
l=A.A(d)
d=m[1]
d.toString
k=A.A(d)
p=6
j=null
p=10
d=m[3]
d.toString
s=13
return A.R(A.bP(A.B(v.G.fetch(l,{integrity:A.A(d)})),t.m),$async$W)
case 13:j=a9
if(!A.e0(j.ok)){d=A.at("HTTP "+A.n(A.mL(j,"status",t.S)))
throw A.d(d)}p=6
s=12
break
case 10:p=9
a4=o.pop()
i=A.I(a4)
d=A.iQ("DRIVER.ASSET","SQLite WASM fetch or integrity check failed.",i)
throw A.d(d)
s=12
break
case 9:s=6
break
case 12:s=14
return A.R(A.bP(A.B(j.arrayBuffer()),t.a),$async$W)
case 14:h=a9
d=A.ar(h,0,null)
b={}
b["content-type"]="application/wasm"
s=15
return A.R(A.fb(A.B(new v.G.Response(d,{headers:b})),null),$async$W)
case 15:a=a9
n.a=a
g=a
s=J.ab(k,"opfs")?16:18
break
case 16:d=m[2]
d.toString
s=19
return A.R(A.eS("dart-orm/"+A.A(d)),$async$W)
case 19:d=a9
n.c=d
d.toString
g.bN(d,!0)
s=17
break
case 18:if(J.ab(k,"memory")){d=A.iC()
n.d=d
g.bN(d,!0)}else throw A.d(B.al)
case 17:d=J.ab(k,"memory")?":memory:":"/database"
a0=g.di(d)
n.b=a0
f=a0
n.e=new A.eZ(f,A.d9(t.S,t.al))
d=J.ab(k,"memory")?"memory":"delete"
e=A.mD(f,B.R,!0,d)
d=g.a.a
a1=d.b
d=d.d
A.av(a1,A.c(d.sqlite3_libversion()),null)
A.av(a1,A.c(d.sqlite3_sourceid()),null)
d=A.x([A.c(d.sqlite3_libversion_number()),e],t.eQ)
q=d
s=1
break
p=2
s=8
break
case 6:p=5
a5=o.pop()
n.C()
throw a5
s=8
break
case 5:s=2
break
case 8:case 4:if(n.b==null)throw A.d(B.am)
switch(a6){case"execute":d=n.e
d.toString
q=A.jP(d.a9(A.jO(a7)))
s=1
break A
case"cursor":d=n.e
d.toString
q=d.dj(A.jO(a7))
s=1
break A
case"fetch":a7.toString
t.c.a(a7)
d=n.e
d.toString
a1=a7[0]
a1.toString
a1=A.c(A.Q(a1))
a2=a7[1]
a2.toString
a2=A.c(A.Q(a2))
if(a2<1)A.u(A.ax(a2,"count",null))
a3=d.b.j(0,a1)
if(a3==null)A.u(B.ao)
q=A.jP(a3.d4(a2))
s=1
break A
case"release":d=n.e
d.toString
a7.toString
d=d.b.am(0,A.c(A.Q(a7)))
if(d!=null)d.C()
q=null
s=1
break A
case"close":n.C()
q=null
s=1
break A
default:throw A.d(B.ap)}case 1:return A.aJ(q,r)
case 2:return A.aI(o.at(-1),r)}})
return A.aK($async$W,r)},
C(){var s,r,q=this,p=q.e
if(p!=null)p.C()
else{p=q.b
if(p!=null)p.C()}q.b=q.e=null
s=q.c
if(s!=null){p=q.a
if(p!=null)p.a.bR(s)
p=s.d
if(p!=null){p.b.close()
p.c.close()
p.d.close()}s.d=null}r=q.d
if(r!=null){p=q.a
if(p!=null)p.a.bR(r)}q.d=q.c=null}}
A.eZ.prototype={
a9(a){var s,r,q,p,o,n,m,l,k,j=this.a,i=j.al(a.a,!0)
try{s=i.b2(new A.b7(A.jN(a.b)))
r=A.x([],t.D)
for(p=s,o=p.d,n=t.X,m=-1;++m,m<o.length;){l=A.hE(o[m],!1,n)
l.$flags=3
q=new A.N(p,l)
k=q.b
k=A.x(k.slice(0),A.am(k))
J.kk(r,k)}p=s.a
o=i.a
if(A.c(o.c.d.sqlite3_stmt_readonly(o.b))!==0)j=0
else{j=j.b
j=A.c(j.a.d.sqlite3_changes(j.b))}return new A.cj(r,p,j)}finally{i.C()}},
dj(a){var s,r,q,p,o=this.a.al(a.a,!0)
try{r=o.a
if(A.c(r.c.d.sqlite3_stmt_readonly(r.b))===0)throw A.d(B.ah)
s=++this.c
r=o
q=A.jN(a.b)
r.aG()
r.Y()
r.az(new A.b7(q))
q=r.gaC()
r.gbn()
q=new A.dE(r,q,B.z)
q.aA()
r.f=!1
r.w=q
this.b.A(0,s,new A.dJ(o,q,B.ac))
return s}catch(p){o.C()
throw p}},
C(){var s,r,q=this
if(q.d)return
q.d=!0
for(s=q.b,r=new A.b8(s,s.r,s.e,A.S(s).h("b8<2>"));r.p();)r.d.C()
if(s.a>0){s.b=s.c=s.d=s.e=s.f=null
s.a=0
s.aK()}q.a.C()}}
A.dJ.prototype={
d4(a){var s,r,q,p=this
if(p.c)return new A.cj(B.ab,p.d,0)
s=A.x([],t.D)
for(r=p.b;s.length<a;){if(!r.p()){p.d=r.a
p.C()
break}q=r.x
q===$&&A.D()
q=q.b
q=A.x(q.slice(0),A.am(q))
B.b.t(s,q)}r=r.a
p.d=r
return new A.cj(s,r,0)},
C(){if(this.c)return
this.c=!0
this.a.C()}}
A.fU.prototype={
$1(a){var s,r,q,p,o,n,m
if(a.j(0,0)==null||a.j(0,1)==null)s=null
else{s=A.ay(a.j(0,0))
r=A.ay(a.j(0,1))
q=A.c(a.j(0,2))
p=A.c(a.j(0,3))
if(!(p>=0&&p<6))return A.b(B.i,p)
p=B.i[p]
t.U.a(r)
A.hB(q)
o=r.a
n=o.m(0,$.E())
if(n===0)A.u(A.aY("Division by zero"))
m=r.b-s.b+q
s=s.a
s=s.q(0,m>0?A.O(10).J(m):$.Z())
s=A.hz(s,o.q(0,m<0?A.O(10).J(-m):$.Z()),q,p).i(0)}return s},
$S:3}
A.fV.prototype={
$1(a){var s,r,q
if(a.j(0,0)==null)s=null
else{s=A.ay(a.j(0,0))
r=A.c(a.j(0,1))
q=A.c(a.j(0,2))
if(!(q>=0&&q<6))return A.b(B.i,q)
q=s.bO(r,B.i[q]).i(0)
s=q}return s},
$S:3}
A.fW.prototype={
$1(a){var s,r,q,p
if(a.j(0,0)==null)s=null
else{s=A.ay(a.j(0,0))
r=A.c(a.j(0,1))
q=A.c(a.j(0,2))
A.ix(r,q)
p=s.bO(q,B.t)
if(!p.bG(r,q))A.u(A.aV("Decimal does not fit NUMERIC("+r+", "+q+")."))
s=p.i(0)}return s},
$S:3}
A.fX.prototype={
$1(a){var s
if(typeof a.j(0,0)=="string"){s=A.hA(A.A(a.j(0,0)))
s=s==null?null:s.bG(A.c(a.j(0,1)),A.c(a.j(0,2)))
s=s===!0}else s=!1
return s?1:0},
$S:39}
A.fY.prototype={
$2(a,b){var s,r,q
if(a==b)return 0
if(a==null)return-1
if(b==null)return 1
s=A.hA(a)
r=A.hA(b)
q=s!=null
if(q&&r!=null)return s.m(0,r)
if(q)return-1
if(r!=null)return 1
return B.c.m(a,b)},
$S:16}
A.fZ.prototype={
$1(a){var s,r,q,p
if(a.j(0,0)==null||a.j(0,1)==null)return null
s=A.ay(a.j(0,0))
r=A.ay(a.j(0,1))
q=this.a
A:{if("add"===q){p=s.S(0,r)
break A}if("sub"===q){p=s.S(0,new A.az(r.a.D(0),r.b))
break A}p=A.bt(s.a.q(0,r.a),s.b+r.b)
break A}return p.i(0)},
$S:3}
A.bi.prototype={
ai(a,b,c){var s,r=this
if(r.c===0){r.a=b.a
r.b=b.b}else{s=b.b
if(s>r.b){r.a=r.a.q(0,A.O(10).J(s-r.b))
r.b=s}r.a=r.a.S(0,b.a.q(0,A.O(c)).q(0,A.O(10).J(r.b-s)))}if((r.c+=c)===0){r.a=$.E()
r.b=0}},
an(){return this.c===0?null:A.bt(this.a,this.b).i(0)}}
A.dL.prototype={
aS(){return new A.ao(new A.bi($.E()),t.y)},
b7(a,b){t.y.a(b)
if(a.j(0,0)==null)return
b.a.ai(0,A.ay(a.j(0,0)),1)},
bI(a,b){t.y.a(b)
if(a.j(0,0)==null)return
b.a.ai(0,A.ay(a.j(0,0)),-1)},
bS(a){var s=t.y.a(a).a
return s.c===0?null:A.bt(s.a,s.b).i(0)},
bF(a){return t.y.a(a).a.an()},
$ie3:1}
A.bD.prototype={
an(){var s,r,q,p,o,n=this.a
if(n.c===0)return null
s=A.O(10).J(Math.abs(n.b))
r=n.a
r=r.q(0,n.b<0?s:$.Z())
q=A.O(n.c)
q=q.q(0,n.b>0?s:$.Z())
p=this.b
p.toString
o=this.c
o.toString
A.hB(p)
n=q.m(0,$.E())
if(n===0)A.u(A.aY("Division by zero"))
n=r.q(0,p>0?A.O(10).J(p):$.Z())
return A.hz(n,q.q(0,p<0?A.O(10).J(-p):$.Z()),p,o).i(0)}}
A.dK.prototype={
aS(){return new A.ao(new A.bD(new A.bi($.E())),t._)},
b7(a,b){var s,r=t._.a(b).a,q=A.c(a.j(0,1)),p=A.c(a.j(0,2))
if(!(p>=0&&p<6))return A.b(B.i,p)
s=B.i[p]
p=r.b
if(p!=null)p=p!==q||r.c!==s
else p=!1
if(p)A.u(A.J("Average scale and rounding must be constant.",null))
r.b=q
r.c=s
if(a.j(0,0)!=null)r.a.ai(0,A.ay(a.j(0,0)),1)},
bI(a,b){t._.a(b)
if(a.j(0,0)!=null)b.a.a.ai(0,A.ay(a.j(0,0)),-1)},
bS(a){return t._.a(a).a.an()},
bF(a){return t._.a(a).a.an()},
$ie3:1}
A.dR.prototype={}
A.h4.prototype={
$3(a,b,c){var s,r,q,p,o,n,m
A:{if("time"===b){s=A.ky(a).a
s=A.hH(s+A.jC(s,c,!1))
break A}if("local_datetime"===b){s=A.kx(a).bT(c)
break A}if("instant"===b){r=A.fR(A.hY(a))
q=A.hF(A.hG(A.eO(r),A.eM(r),A.eJ(r)),A.eB(A.eK(r),A.eL(r),A.eN(r),A.hJ(r)*1000+r.b)).bT(c)
p=q.a
s=q.b.a
o=B.a.l(s,36e8)
n=B.a.n(B.a.l(s,6e7),60)
m=B.a.n(B.a.l(s,1e6),60)
s=B.a.n(s,1e6)
s=A.fR(A.it(p.a,p.b,p.c,o,n,m,B.a.l(s,1000),B.a.n(s,1000)))
break A}s=A.u(A.J("Unknown temporal storage.",null))}return s},
$S:49}
A.h_.prototype={
$1(a){var s,r,q,p,o
if(a.j(0,0)==null)return null
s=A.A(a.j(0,1))
r=A.c(a.j(0,2))
q=this.a
p=a.j(0,0)
p.toString
o=q.$3(p,s,r)
if(this.b){p=a.j(0,0)
p.toString
return J.ab(o,q.$3(p,s,6))?1:0}return o instanceof A.a3?A.jq(o):J.b4(o)},
$S:12}
A.h0.prototype={
$1(a){return a.j(0,0)==null?null:A.jq(t.k.a(A.hY(a.j(0,0))))},
$S:12}
A.h2.prototype={
$1$2(a,b,c){A.mC(c,c.h("t<0>"),"T","call")
this.a.bz(new A.h3(c.h("0?(h)").a(b)),"orm_"+a+"_v1")},
$2(a,b){return this.$1$2(a,b,t.q)},
$S:23}
A.h3.prototype={
$2(a,b){var s,r,q
if(a==b)return 0
if(a==null)return-1
if(b==null)return 1
s=this.a
r=s.$1(a)
q=s.$1(b)
s=r!=null
if(s&&q!=null)return J.km(r,q)
if(s)return-1
if(q!=null)return 1
return B.c.m(a,b)},
$S:16}
A.h1.prototype={
$1(a){var s,r
try{s=A.hY(a)
return s}catch(r){if(A.I(r) instanceof A.v)return null
else throw r}},
$S:24}
A.hp.prototype={
$1(a){return A.A(a)},
$S:25}
A.hq.prototype={
$1(a){var s=J.ko(t.W.a(a),A.n6(),t.X)
s=A.da(s,s.$ti.h("V.E"))
return s},
$S:21}
A.ci.prototype={}
A.hy.prototype={}
A.a0.prototype={
i(a){return"OrmException("+this.a+"): "+this.b}}
A.aA.prototype={
aH(){return"DecimalRounding."+this.b}}
A.az.prototype={
S(a,b){var s=this.b,r=b.b,q=Math.max(s,r)
return A.bt(this.a.q(0,A.O(10).J(q-s)).S(0,b.a.q(0,A.O(10).J(q-r))),q)},
bO(a,b){var s
A.hB(a)
s=this.b
if(a>=s)return this
return A.hz(this.a,A.O(10).J(s-a),a,b)},
bG(a,b){var s,r
A.ix(a,b)
s=this.a
r=s.m(0,$.E())
if(r!==0){r=this.b
if(r<=b)s=(s.a?s.D(0):s).i(0).length-r<=a-b
else s=!1}else s=!0
return s},
m(a,b){var s,r,q,p,o,n,m
t.U.a(b)
s=this.a
r=b.a
if(s.gU(0)!==r.gU(0))return B.a.m(s.gU(0),r.gU(0))
q=s.m(0,$.E())
if(q===0)return 0
q=this.b
p=(s.a?s.D(0):s).i(0).length-q
o=b.b
n=(r.a?r.D(0):r).i(0).length-o
if(p!==n)return B.a.m(p,n)*s.gU(0)
m=Math.max(q,o)
return s.q(0,A.O(10).J(m-q)).m(0,r.q(0,A.O(10).J(m-o)))},
I(a,b){var s
if(b==null)return!1
if(b instanceof A.az){s=this.a.m(0,b.a)
s=s===0&&this.b===b.b}else s=!1
return s},
gu(a){return A.eG(this.a,this.b,B.f,B.f)},
i(a){var s,r=this.a,q=r.a,p=(q?r.D(0):r).i(0),o=q?"-":""
r=this.b
if(r<=0)return o+p+B.c.q("0",-r)
q=p.length
if(r>=q)return o+"0."+B.c.q("0",r-q)+p
s=q-r
return o+B.c.a1(p,0,s)+"."+B.c.b8(p,s)},
$it:1}
A.ap.prototype={
bs(a){var s=this.d
if(a<0-s||a>2147483493-s)throw A.d(A.aV("Date addition exceeds the supported range."))
return A.iL(s+a)},
gaB(){var s=this.a
return B.c.R(B.a.i(s<=0?1-s:s),4,"0")+"-"+B.c.R(B.a.i(this.b),2,"0")+"-"+B.c.R(B.a.i(this.c),2,"0")},
i(a){var s=this.gaB()
return s+(this.a<=0?" BC":"")},
m(a,b){return B.a.m(this.d,t.A.a(b).d)},
I(a,b){if(b==null)return!1
return b instanceof A.ap&&this.d===b.d},
gu(a){return B.a.gu(this.d)},
$it:1}
A.aj.prototype={
i(a){var s=this.a
return B.c.R(B.a.i(B.a.l(s,36e8)),2,"0")+":"+B.c.R(B.a.i(B.a.n(B.a.l(s,6e7),60)),2,"0")+":"+B.c.R(B.a.i(B.a.n(B.a.l(s,1e6),60)),2,"0")+"."+B.c.R(B.a.i(B.a.n(s,1e6)),6,"0")},
m(a,b){return B.a.m(this.a,t.t.a(b).a)},
I(a,b){if(b==null)return!1
return b instanceof A.aj&&this.a===b.a},
gu(a){return B.a.gu(this.a)},
$it:1}
A.aq.prototype={
bT(a){var s=864e8,r=this.b.a,q=this.a,p=A.iy(A.jC(r,a,q.d<2451545)).a,o=A.fS(p,s),n=r+B.a.n(p,s)
return A.hF(q.bs(o+B.a.l(n,s)),A.hH(B.a.n(n,s)))},
i(a){var s=this.a,r=s.gaB(),q=this.b.i(0)
s=s.a<=0?" BC":""
return r+" "+q+s},
m(a,b){var s
t.B.a(b)
s=B.a.m(this.a.d,b.a.d)
return s===0?B.a.m(this.b.a,b.b.a):s},
I(a,b){var s,r
if(b==null)return!1
s=!1
if(b instanceof A.aq){r=b.a
if(this.a.d===r.d)s=this.b.a===b.b.a}return s},
gu(a){return A.eG(this.a,this.b,B.f,B.f)},
$it:1}
A.ck.prototype={
i(a){var s,r,q=this,p=q.e
p=p==null?"":"while "+p+", "
p="SqliteException("+q.c+"): "+p+q.a
s=q.b
if(s!=null)p=p+", "+s
s=q.f
if(s!=null){r=q.d
r=r!=null?" (at position "+A.n(r)+"): ":": "
s=p+"\n  Causing statement"+r+s
p=q.r
if(p!=null){r=A.am(p)
r=s+(", parameters: "+new A.a5(p,r.h("h(1)").a(new A.eY()),r.h("a5<1,h>")).bJ(0,", "))
p=r}else p=s}return p.charCodeAt(0)==0?p:p}}
A.eY.prototype={
$1(a){if(t.I.b(a))return"blob ("+a.length+" bytes)"
else return J.b4(a)},
$S:27}
A.ao.prototype={}
A.b5.prototype={}
A.cY.prototype={
aN(a){var s=B.h.P(a)
if(s.length>255)throw A.d(A.ax(a,"functionName","Must not exceed 255 bytes when utf-8 encoded"))
return new Uint8Array(A.lZ(s))},
by(a,b,c,d,e){var s,r,q,p,o,n,m,l,k,j,i=null
e.h("e3<0>").a(c)
s=this.aN(d)
r=A.i7(!0,!0,!1)
q=new A.eq(e,c)
p=this.b
o=t.fB
n=o.a(new A.eo(e,c))
m=t.bN
l=m.a(new A.em(q,c))
m=m.a(new A.er(q,c))
q=o.a(new A.en(c,q))
o=p.a
k=o.V(s,1)
o=o.d
j=A.h8(o,"dart_sqlite3_create_window_function",[p.b,k,a.a,r,new A.a7(i,m,n,q,l,i)],t.S)
o.dart_sqlite3_free(k)
if(j!==0)A.cM(this,j,i,i,i)},
a7(a,b,c,d,e){var s,r
t.e.a(d)
s=this.aN(e)
r=this.b.c5(A.i7(!0,c,!1),s,a.a,new A.et(d))
if(r!==0)A.cM(this,r,null,null,null)},
aT(a,b,c,d){return this.a7(a,b,!0,c,d)},
bz(a,b){var s,r,q,p,o,n,m=null
t.aa.a(a)
s=this.b
r=this.aN(b)
q=A.i7(!1,!1,!1)
p=s.a
o=p.V(r,1)
p=p.d
n=A.c(p.dart_sqlite3_create_collation(s.b,o,q,new A.a7(m,m,m,m,m,a)))
p.dart_sqlite3_free(o)
if(n!==0)A.cM(this,n,m,m,m)},
C(){var s,r,q,p=this
if(p.r)return
p.r=!0
s=p.b
r=s.b4()
q=r!==0?A.i6(p.a,s,r,"closing database",null,null):null
if(q!=null)throw A.d(q)},
a9(a){var s,r,q,p=this,o=B.y
if(J.ac(o)===0){if(p.r)A.u(A.at("This database has already been closed"))
r=p.b
q=r.a
s=q.V(B.h.P(a),1)
q=q.d
r=A.h8(q,"sqlite3_exec",[r.b,s,0,0,0],t.S)
q.dart_sqlite3_free(s)
if(r!==0)A.cM(p,r,"executing",a,o)}else{s=p.al(a,!0)
try{r=s
q=t.W.a(o)
r.aG()
r.Y()
r.az(new A.b7(q))
r.cn()}finally{s.C()}}},
ct(a,b,a0,a1,a2){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c=this
if(c.r)A.u(A.at("This database has already been closed"))
s=B.h.P(a)
r=c.b
t.L.a(s)
q=r.a
p=q.a2(s)
o=q.d
n=A.c(o.dart_sqlite3_malloc(4))
o=A.c(o.dart_sqlite3_malloc(4))
m=new A.fc(r,p,n,o)
l=A.x([],t.bb)
k=new A.ej(m,l)
for(r=s.length,q=q.b,n=t.a,j=0;j<r;j=e){i=m.b5(j,r-j,0)
h=i.b
if(h!==0){k.$0()
A.cM(c,h,"preparing statement",a,null)}h=n.a(q.buffer)
g=B.a.l(h.byteLength,4)
h=new Int32Array(h,0,g)
f=B.a.B(o,2)
if(!(f<h.length))return A.b(h,f)
e=h[f]-p
d=i.a
if(d!=null)B.b.t(l,new A.bB(d,c,new A.cF(!1).aE(s,j,e,!0)))
if(l.length===a0){j=e
break}}while(j<r){i=m.b5(j,r-j,0)
h=n.a(q.buffer)
g=B.a.l(h.byteLength,4)
h=new Int32Array(h,0,g)
f=B.a.B(o,2)
if(!(f<h.length))return A.b(h,f)
j=h[f]-p
d=i.a
if(d!=null){B.b.t(l,new A.bB(d,c,""))
k.$0()
throw A.d(A.ax(a,"sql","Had an unexpected trailing statement."))}else if(i.b!==0){k.$0()
throw A.d(A.ax(a,"sql","Has trailing data after the first sql statement:"))}}m.C()
return l},
al(a,b){var s=this.ct(a,!0,1,!1,!0)
if(s.length===0)throw A.d(A.ax(a,"sql","Must contain an SQL statement."))
return B.b.gd5(s)},
ap(a){var s,r=B.y,q=this.al(a,!0)
try{s=q.b2(new A.b7(t.W.a(r)))
return s}finally{q.C()}},
$ikz:1}
A.eq.prototype={
$1(a){var s,r,q,p,o=this.a.h("ao<0>?").a(a.gbA())
if(o==null){o=this.b.aS()
s=a.gbi()
r=a.c
q=r.c++
r.d.A(0,q,A.hw(o,null,t.E))
r=A.ak(t.a.a(a.a.b.buffer),0,null)
p=B.a.B(s,2)
r.$flags&2&&A.l(r)
if(!(p<r.length))return A.b(r,p)
r[p]=q
r=o}else r=o
return r},
$S(){return this.a.h("ao<0>(aD)")}}
A.er.prototype={
$2(a,b){t.w.a(b)
A.hZ(a,new A.es(this.b,this.a.$1(a)),b)},
$S:8}
A.es.prototype={
$1(a){return this.a.b7(a,this.b)},
$S:15}
A.eo.prototype={
$1(a){A.js(a,new A.ep(a,this.a,this.b))},
$S:9}
A.ep.prototype={
$0(){var s=this.b.h("ao<0>?").a(this.a.gbA()),r=this.c
return r.bF(s==null?r.aS():s)},
$S:17}
A.en.prototype={
$1(a){A.js(a,new A.ek(this.a,this.b,a))},
$S:9}
A.ek.prototype={
$0(){return this.a.bS(this.b.$1(this.c))},
$S:17}
A.em.prototype={
$2(a,b){t.w.a(b)
A.hZ(a,new A.el(this.b,this.a.$1(a)),b)},
$S:8}
A.el.prototype={
$1(a){return this.a.bI(a,this.b)},
$S:15}
A.et.prototype={
$2(a,b){A.hZ(a,this.a,t.w.a(b))},
$S:8}
A.ej.prototype={
$0(){var s,r,q,p,o,n
this.a.C()
for(s=this.b,r=s.length,q=0;q<s.length;s.length===r||(0,A.hr)(s),++q){p=s[q]
if(!p.r){p.r=!0
if(!p.f){o=p.a
A.c(o.c.d.sqlite3_reset(o.b))
p.f=!0}p.w=null
o=p.a
n=o.c
A.c(n.d.sqlite3_finalize(o.b))
n=n.w
if(n!=null){n=n.a
if(n!=null)n.unregister(o.d)}}}},
$S:0}
A.dz.prototype={
gk(a){return this.a.b},
j(a,b){var s,r,q=this.a,p=q.b
if(0>b||b>=p)A.u(A.ew(b,p,this,null,"index"))
s=this.b
if(!(b>=0&&b<s.length))return A.b(s,b)
r=s[b]
if(r==null){q=A.l3(q.j(0,b))
B.b.A(s,b,q)}else q=r
return q},
A(a,b,c){throw A.d(A.J("The argument list is unmodifiable",null))},
$ias:1}
A.eX.prototype={
bH(){var s=null,r=A.c(this.a.a.d.sqlite3_initialize())
if(r!==0)throw A.d(A.l7(s,s,r,"Error returned by sqlite3_initialize",s,s,s))},
di(a){var s,r,q,p,o,n,m,l,k,j,i
this.bH()
switch(2){case 2:break}s=this.a
r=s.a
q=r.V(B.h.P(a),1)
p=r.d
o=A.c(p.dart_sqlite3_malloc(4))
n=A.c(p.sqlite3_open_v2(q,o,6,0))
m=A.ak(t.a.a(r.b.buffer),0,null)
l=B.a.B(o,2)
if(!(l<m.length))return A.b(m,l)
k=m[l]
p.dart_sqlite3_free(q)
p.dart_sqlite3_free(0)
m=new A.e()
j=new A.dA(r,k,m)
r=r.r
if(r!=null)r.bv(j,k,m)
if(n!==0){i=A.i6(s,j,n,"opening the database",null,null)
j.b4()
throw A.d(i)}A.c(p.sqlite3_extended_result_codes(k,1))
return new A.cY(s,j,!1)},
bN(a,b){var s,r
this.bH()
s=this.a.a
r=A.c(s.d.dart_sqlite3_register_vfs(s.V(B.h.P(a.a),1),a,1))
if(r===0)A.u(A.at("could not register vfs"))
s=$.ic()
s.$ti.h("1?").a(r)
s.a.set(a,r)}}
A.bB.prototype={
gaC(){var s,r,q,p,o,n,m,l,k,j=this.a,i=j.c
j=j.b
s=i.d
r=A.c(s.sqlite3_column_count(j))
q=A.x([],t.s)
for(p=t.L,i=i.b,o=t.a,n=0;n<r;++n){m=A.c(s.sqlite3_column_name(j,n))
l=o.a(i.buffer)
k=A.hO(i,m)
l=p.a(new Uint8Array(l,m,k))
q.push(new A.cF(!1).aE(l,0,null,!0))}return q},
gbn(){return null},
ab(a,b){A.cM(this.b,a,b,this.d,this.e)},
aG(){if(this.r||this.b.r)throw A.d(A.at("Tried to operate on a released prepared statement"))},
cn(){var s,r=this,q=r.f=!1,p=r.a,o=p.b
p=p.c.d
do s=A.c(p.sqlite3_step(o))
while(s===100)
r.Y()
if(s!==0?s!==101:q)r.ab(s,"executing statement")},
cu(){var s,r,q,p,o,n,m,l=this,k=A.x([],t.D),j=l.f=!1
for(s=l.a,r=s.b,s=s.c.d,q=-1;p=A.c(s.sqlite3_step(r)),p===100;){if(q===-1)q=A.c(s.sqlite3_column_count(r))
o=[]
for(n=0;n<q;++n)o.push(l.bj(n))
B.b.t(k,o)}l.Y()
if(p!==0?p!==101:j)l.ab(p,"selecting from statement")
m=l.gaC()
l.gbn()
j=new A.dq(k,m,B.z)
j.aA()
return j},
bj(a){var s,r,q=this.a,p=q.c
q=q.b
s=p.d
switch(A.c(s.sqlite3_column_type(q,a))){case 1:q=t.C.a(s.sqlite3_column_int64(q,a))
p=v.G
return A.e0(p.Number.isSafeInteger(A.Q(p.Number(q))))?A.c(A.Q(p.Number(q))):A.hU(A.A(q.toString()),null)
case 2:return A.Q(s.sqlite3_column_double(q,a))
case 3:return A.av(p.b,A.c(s.sqlite3_column_text(q,a)),null)
case 4:r=A.c(s.sqlite3_column_bytes(q,a))
return A.j_(p.b,A.c(s.sqlite3_column_blob(q,a)),r)
case 5:default:return null}},
ce(a){var s,r=a.length,q=this.a,p=A.c(q.c.d.sqlite3_bind_parameter_count(q.b))
if(r!==p)A.u(A.ax(a,"parameters","Expected "+p+" parameters, got "+r))
q=a.length
if(q===0)return
for(s=1;s<=a.length;++s)this.cf(a[s-1],s)
this.e=a},
cf(a,b){var s,r,q,p,o=this
A:{if(a==null){s=o.a
s=A.c(s.c.d.sqlite3_bind_null(s.b,b))
break A}if(A.bJ(a)){s=o.a
s=A.c(s.c.d.sqlite3_bind_int64(s.b,b,t.C.a(v.G.BigInt(a))))
break A}if(a instanceof A.z){s=o.a
s=A.c(s.c.d.sqlite3_bind_int64(s.b,b,t.C.a(v.G.BigInt(A.il(a).i(0)))))
break A}if(A.cI(a)){s=o.a
r=a?1:0
s=A.c(s.c.d.sqlite3_bind_int64(s.b,b,t.C.a(v.G.BigInt(r))))
break A}if(typeof a=="number"){s=o.a
s=A.c(s.c.d.sqlite3_bind_double(s.b,b,a))
break A}if(typeof a=="string"){s=o.a
q=B.h.P(a)
p=s.c
p=A.c(p.d.dart_sqlite3_bind_text(s.b,b,p.a2(q),q.length))
s=p
break A}s=t.L
if(s.b(a)){p=o.a
s.a(a)
s=p.c
s=A.c(s.d.dart_sqlite3_bind_blob(p.b,b,s.a2(a),J.ac(a)))
break A}s=o.cd(a,b)
break A}if(s!==0)o.ab(s,"binding parameter")},
cd(a,b){var s
A.bl(a)
if(a instanceof A.dR){s=this.a
s=A.c(s.c.d.sqlite3_bind_double(s.b,b,a.a))
if(s!==0)this.ab(s,"binding parameter")
return 0}throw A.d(A.ax(a,"params["+b+"]","Allowed parameters must either be null or bool, int, num, String or List<int>."))},
az(a){A:{this.ce(a.a)
break A}},
Y(){var s,r=this
if(!r.f){s=r.a
A.c(s.c.d.sqlite3_reset(s.b))
r.f=!0}r.w=null},
C(){var s,r,q=this
if(!q.r){q.r=!0
q.Y()
s=q.a
r=s.c
A.c(r.d.sqlite3_finalize(s.b))
r=r.w
if(r!=null)r.bC(s.d)}},
b2(a){var s=this
s.aG()
s.Y()
s.az(a)
return s.cu()}}
A.dE.prototype={
gv(){var s=this.x
s===$&&A.D()
return s},
p(){var s,r,q,p,o=this,n=o.r
if(n.r||n.w!==o)return!1
s=n.a
r=s.b
s=s.c.d
q=A.c(s.sqlite3_step(r))
if(q===100){if(!o.y){o.w=A.c(s.sqlite3_column_count(r))
o.a=t.dy.a(n.gaC())
o.aA()
o.y=!0}s=[]
for(p=0;p<o.w;++p)s.push(n.bj(p))
o.x=new A.N(o,A.db(s,t.X))
return!0}if(q!==5){n.w=null
n.Y()}if(q!==0&&q!==101)n.ab(q,"iterating through statement")
return!1}}
A.d1.prototype={
bU(a,b){return this.d.a6(a)?1:0},
bX(a,b){this.d.am(0,a)},
bZ(a){return A.A(A.B(new v.G.URL(a,"file:///")).pathname)},
ao(a,b){var s,r=a.a
if(r==null)r=A.kH(this.b,"/")
s=this.d
if(!s.a6(r))if((b&4)!==0)s.A(0,r,new A.bf(new Uint8Array(0),0))
else throw A.d(A.f3(14))
return new A.bF(new A.dO(this,r,(b&8)!==0),0)},
c0(a){}}
A.dO.prototype={
bL(a,b){var s,r=this.a.d.j(0,this.b)
if(r==null||r.b<=b)return 0
s=Math.min(a.length,r.b-b)
B.e.L(a,0,s,J.ii(B.e.gaP(r.a),0,r.b),b)
return s},
bV(){return this.d>=2?1:0},
bW(){if(this.c)this.a.d.am(0,this.b)},
bY(){return this.a.d.j(0,this.b).b},
c_(a){this.d=a},
c1(a){},
c2(a){var s=this.a.d,r=this.b,q=s.j(0,r)
if(q==null){s.A(0,r,new A.bf(new Uint8Array(0),0))
s.j(0,r).sk(0,a)}else q.sk(0,a)},
c3(a){this.d=a},
c4(a,b){var s,r=this.a.d,q=this.b,p=r.j(0,q)
if(p==null){p=new A.bf(new Uint8Array(0),0)
r.A(0,q,p)}s=b+a.length
if(s>p.b)p.sk(0,s)
p.T(0,b,s,a)}}
A.hk.prototype={
$1(a){return A.A(a).length!==0},
$S:32}
A.bs.prototype={
aA(){var s,r,q,p,o=A.d9(t.N,t.S)
for(s=this.a,r=s.length,q=0;q<s.length;s.length===r||(0,A.hr)(s),++q){p=s[q]
o.A(0,p,B.b.dc(this.a,p))}this.c=o}}
A.c_.prototype={$iK:1}
A.dq.prototype={
gG(a){return new A.dS(this)},
j(a,b){var s=this.d
if(!(b>=0&&b<s.length))return A.b(s,b)
return new A.N(this,A.db(s[b],t.X))},
A(a,b,c){t.fI.a(c)
throw A.d(A.aY("Can't change rows from a result set"))},
gk(a){return this.d.length},
$ii:1,
$if:1,
$ij:1}
A.N.prototype={
j(a,b){var s,r
if(typeof b!="string"){if(A.bJ(b)){s=this.b
if(b>>>0!==b||b>=s.length)return A.b(s,b)
return s[b]}return null}r=this.a.c.j(0,b)
if(r==null)return null
s=this.b
if(r>>>0!==r||r>=s.length)return A.b(s,r)
return s[r]},
gaZ(){return this.a.a},
$iba:1}
A.dS.prototype={
gv(){var s=this.a,r=s.d,q=this.b
if(!(q>=0&&q<r.length))return A.b(r,q)
return new A.N(s,A.db(r[q],t.X))},
p(){return++this.b<this.a.d.length},
$iK:1}
A.dT.prototype={}
A.dU.prototype={}
A.dW.prototype={}
A.dX.prototype={}
A.eH.prototype={
aH(){return"OpenMode."+this.b}}
A.cU.prototype={}
A.b7.prototype={$il9:1}
A.aZ.prototype={
i(a){return"VfsException("+this.a+")"}}
A.eW.prototype={}
A.H.prototype={}
A.cR.prototype={}
A.cQ.prototype={$iX:1}
A.dC.prototype={
bR(a){var s=$.ic(),r=s.a.get(a)
if(r==null)throw A.d(A.at("vfs has not been registered"))
A.c(this.a.d.dart_sqlite3_unregister_vfs(r))},
$il0:1}
A.dA.prototype={
b4(){var s=this.a,r=s.r
if(r!=null)r.bC(this.c)
return A.c(s.d.sqlite3_close_v2(this.b))},
c6(a,b,c,d,e,f){var s,r,q,p,o,n=null,m=t.cN
m.a(e)
m.a(f)
t.ci.a(d)
m=this.a
s=m.V(b,1)
r=e==null
q=!r?new A.a7(e,n,n,n,n,n):new A.a7(n,f,d,n,n,n)
m=m.d
p=r?1:0
o=A.h8(m,"dart_sqlite3_create_function_v2",[this.b,s,c,a,p,q],t.S)
m.dart_sqlite3_free(s)
return o},
c5(a,b,c,d){return this.c6(a,b,c,null,d,null)},
$il1:1}
A.fc.prototype={
C(){var s=this,r=s.a.a.d
r.dart_sqlite3_free(s.b)
r.dart_sqlite3_free(s.c)
r.dart_sqlite3_free(s.d)},
b5(a,b,c){var s,r,q,p=this,o=p.a,n=o.a,m=p.c
o=A.h8(n.d,"sqlite3_prepare_v3",[o.b,p.b+a,b,c,m,p.d],t.S)
s=A.ak(t.a.a(n.b.buffer),0,null)
m=B.a.B(m,2)
if(!(m<s.length))return A.b(s,m)
r=s[m]
if(r===0)q=null
else{m=new A.e()
q=new A.dD(r,n,m)
n=n.w
if(n!=null)n.bv(q,r,m)}return new A.cz(q,o)}}
A.dD.prototype={$il2:1}
A.b_.prototype={
gbi(){var s=A.c(this.a.d.sqlite3_aggregate_context(this.b,4))
if(s===0)throw A.d(A.at("Internal error while allocating sqlite3 aggregate context (OOM?)"))
return s},
gbA(){var s,r=this.gbi(),q=A.ak(t.a.a(this.a.b.buffer),0,null),p=B.a.B(r,2)
if(!(p<q.length))return A.b(q,p)
s=q[p]
if(s===0)return null
else return this.c.d.j(0,s)},
b6(a){var s=B.h.P(a),r=this.a,q=r.a2(s)
r=r.d
r.sqlite3_result_error(this.b,q,s.length)
r.dart_sqlite3_free(q)},
$iaD:1}
A.au.prototype={$icc:1}
A.bC.prototype={
j(a,b){var s=this.a,r=A.ak(t.a.a(s.b.buffer),0,null),q=B.a.B(this.c+b*4,2)
if(!(q<r.length))return A.b(r,q)
return new A.au(s,r[q])},
A(a,b,c){t.gV.a(c)
throw A.d(A.aY("Setting element in WasmValueList"))},
gk(a){return this.b}}
A.cX.prototype={
dg(a){var s
A.c(a)
s=this.b
s===$&&A.D()
A.mW("[sqlite3] "+A.av(s,a,null))},
de(a,b){var s,r,q,p,o
t.C.a(a)
A.c(b)
s=A.c(A.Q(v.G.Number(a)))*1000
if(s<-864e13||s>864e13)A.u(A.P(s,-864e13,864e13,"millisecondsSinceEpoch",null))
A.h9(!1,"isUtc",t.v)
r=new A.a3(s,0,!1)
q=this.b
q===$&&A.D()
p=A.kV(t.a.a(q.buffer),b,8)
p.$flags&2&&A.l(p)
q=p.length
if(0>=q)return A.b(p,0)
p[0]=A.eN(r)
if(1>=q)return A.b(p,1)
p[1]=A.eL(r)
if(2>=q)return A.b(p,2)
p[2]=A.eK(r)
if(3>=q)return A.b(p,3)
p[3]=A.eJ(r)
if(4>=q)return A.b(p,4)
p[4]=A.eM(r)-1
if(5>=q)return A.b(p,5)
p[5]=A.eO(r)-1900
o=B.a.n(A.kX(r),7)
if(6>=q)return A.b(p,6)
p[6]=o},
dS(a,b,c,d,e){var s,r,q,p,o,n,m,l,k,j=null
t.j.a(a)
A.c(b)
A.c(c)
A.c(d)
A.c(e)
p=this.b
p===$&&A.D()
s=new A.eW(A.hN(p,b,j))
try{r=a.ao(s,d)
if(e!==0){o=r.b
n=A.ak(t.a.a(p.buffer),0,j)
m=B.a.B(e,2)
n.$flags&2&&A.l(n)
if(!(m<n.length))return A.b(n,m)
n[m]=o}o=A.ak(t.a.a(p.buffer),0,j)
n=B.a.B(c,2)
o.$flags&2&&A.l(o)
if(!(n<o.length))return A.b(o,n)
o[n]=0
l=r.a
return l}catch(k){o=A.I(k)
if(o instanceof A.aZ){q=o
o=q.a
p=A.ak(t.a.a(p.buffer),0,j)
n=B.a.B(c,2)
p.$flags&2&&A.l(p)
if(!(n<p.length))return A.b(p,n)
p[n]=o}else{p=t.a.a(p.buffer)
p=A.ak(p,0,j)
o=B.a.B(c,2)
p.$flags&2&&A.l(p)
if(!(o<p.length))return A.b(p,o)
p[o]=1}}return j},
dG(a,b,c){var s
t.j.a(a)
A.c(b)
A.c(c)
s=this.b
s===$&&A.D()
return A.a8(new A.e8(a,A.av(s,b,null),c))},
dw(a,b,c,d){var s
t.j.a(a)
A.c(b)
A.c(c)
A.c(d)
s=this.b
s===$&&A.D()
return A.a8(new A.e5(this,a,A.av(s,b,null),c,d))},
dO(a,b,c,d){var s
t.j.a(a)
A.c(b)
A.c(c)
A.c(d)
s=this.b
s===$&&A.D()
return A.a8(new A.ea(this,a,A.av(s,b,null),c,d))},
dU(a,b,c){t.bx.a(a)
A.c(b)
return A.a8(new A.ec(this,A.c(c),b,a))},
e_(a,b){return A.a8(new A.ee(t.j.a(a),A.c(b)))},
dE(a,b){var s,r,q
t.j.a(a)
A.c(b)
s=Date.now()
r=this.b
r===$&&A.D()
q=t.C.a(v.G.BigInt(s))
A.kO(A.iO(t.a.a(r.buffer),0,null),"setBigInt64",b,q,!0,null)
return 0},
dC(a){return A.a8(new A.e7(t.r.a(a)))},
dW(a,b,c,d){return A.a8(new A.ed(this,t.r.a(a),A.c(b),A.c(c),t.C.a(d)))},
e7(a,b,c,d){return A.a8(new A.ei(this,t.r.a(a),A.c(b),A.c(c),t.C.a(d)))},
e3(a,b){return A.a8(new A.eg(t.r.a(a),t.C.a(b)))},
e1(a,b){return A.a8(new A.ef(t.r.a(a),A.c(b)))},
dM(a,b){return A.a8(new A.e9(this,t.r.a(a),A.c(b)))},
dQ(a,b){return A.a8(new A.eb(t.r.a(a),A.c(b)))},
e5(a,b){return A.a8(new A.eh(t.r.a(a),A.c(b)))},
dA(a,b){return A.a8(new A.e6(this,t.r.a(a),A.c(b)))},
dI(a){t.r.a(a)
return 0},
dK(a,b,c){t.r.a(a)
A.c(b)
A.c(c)
return 12},
dY(a){t.r.a(a)
return 4096},
cS(a){t.M.a(a).$0()},
cO(a){return t.ez.a(a).$0()},
cQ(a,b,c,d,e){var s
t.hd.a(a)
A.c(b)
A.c(c)
A.c(d)
t.C.a(e)
s=this.b
s===$&&A.D()
a.$3(b,A.av(s,d,null),A.c(A.Q(v.G.Number(e))))},
cY(a,b,c,d){var s,r
t.V.a(a)
A.c(b)
A.c(c)
A.c(d)
s=a.a
s.toString
r=this.a
r===$&&A.D()
s.$2(new A.b_(r,b,this),new A.bC(r,c,d))},
d1(a,b,c,d){var s,r
t.V.a(a)
A.c(b)
A.c(c)
A.c(d)
s=a.b
s.toString
r=this.a
r===$&&A.D()
s.$2(new A.b_(r,b,this),new A.bC(r,c,d))},
d_(a,b,c,d){var s,r
t.V.a(a)
A.c(b)
A.c(c)
A.c(d)
s=a.e
s.toString
r=this.a
r===$&&A.D()
s.$2(new A.b_(r,b,this),new A.bC(r,c,d))},
d3(a,b){var s,r
t.V.a(a)
A.c(b)
s=a.d
s.toString
r=this.a
r===$&&A.D()
s.$1(new A.b_(r,b,this))},
cW(a,b){var s,r
t.V.a(a)
A.c(b)
s=a.c
s.toString
r=this.a
r===$&&A.D()
s.$1(new A.b_(r,b,this))},
cU(a,b,c,d,e){var s
t.V.a(a)
A.c(b)
A.c(c)
A.c(d)
A.c(e)
s=this.b
s===$&&A.D()
return a.f.$2(A.hN(s,c,b),A.hN(s,e,d))},
cM(a,b){return t.f5.a(a).$1(A.c(b))},
cK(a,b){t.p.a(a)
A.c(b)
return a.geb().$1(b)},
cI(a,b,c){t.p.a(a)
A.c(b)
A.c(c)
return a.gea().$2(b,c)}}
A.e8.prototype={
$0(){return this.a.bX(this.b,this.c)},
$S:0}
A.e5.prototype={
$0(){var s,r=this,q=r.b.bU(r.c,r.d),p=r.a.b
p===$&&A.D()
p=A.ak(t.a.a(p.buffer),0,null)
s=B.a.B(r.e,2)
p.$flags&2&&A.l(p)
if(!(s<p.length))return A.b(p,s)
p[s]=q},
$S:0}
A.ea.prototype={
$0(){var s,r,q=this,p=B.h.P(q.b.bZ(q.c)),o=p.length
if(o>q.d)throw A.d(A.f3(14))
s=q.a.b
s===$&&A.D()
s=A.ar(t.a.a(s.buffer),0,null)
r=q.e
B.e.b3(s,r,p)
o=r+o
s.$flags&2&&A.l(s)
if(!(o>=0&&o<s.length))return A.b(s,o)
s[o]=0},
$S:0}
A.ec.prototype={
$0(){var s,r=this,q=r.a.b
q===$&&A.D()
s=A.ar(t.a.a(q.buffer),r.b,r.c)
q=r.d
if(q!=null)A.ik(s,q.b)
else return A.ik(s,null)},
$S:0}
A.ee.prototype={
$0(){this.a.c0(A.iy(this.b))},
$S:0}
A.e7.prototype={
$0(){return this.a.bW()},
$S:0}
A.ed.prototype={
$0(){var s,r,q=this,p=q.a.b
p===$&&A.D()
p=A.ar(t.a.a(p.buffer),q.c,q.d)
s=q.b.bL(p,A.c(A.Q(v.G.Number(q.e))))
r=p.length
if(s<r){B.e.bE(p,s,r,0)
A.u(B.aD)}},
$S:0}
A.ei.prototype={
$0(){var s=this,r=s.a.b
r===$&&A.D()
s.b.c4(A.ar(t.a.a(r.buffer),s.c,s.d),A.c(A.Q(v.G.Number(s.e))))},
$S:0}
A.eg.prototype={
$0(){return this.a.c2(A.c(A.Q(v.G.Number(this.b))))},
$S:0}
A.ef.prototype={
$0(){return this.a.c1(this.b)},
$S:0}
A.e9.prototype={
$0(){var s,r=this.b.bY(),q=this.a.b
q===$&&A.D()
q=A.ak(t.a.a(q.buffer),0,null)
s=B.a.B(this.c,2)
q.$flags&2&&A.l(q)
if(!(s<q.length))return A.b(q,s)
q[s]=r},
$S:0}
A.eb.prototype={
$0(){return this.a.c_(this.b)},
$S:0}
A.eh.prototype={
$0(){return this.a.c3(this.b)},
$S:0}
A.e6.prototype={
$0(){var s,r=this.b.bV(),q=this.a.b
q===$&&A.D()
q=A.ak(t.a.a(q.buffer),0,null)
s=B.a.B(this.c,2)
q.$flags&2&&A.l(q)
if(!(s<q.length))return A.b(q,s)
q[s]=r},
$S:0}
A.a7.prototype={}
A.f9.prototype={
cF(){var s={}
s.dart=new A.fa(this).$0()
return s},
aj(a){var s=0,r=A.aM(t.m),q,p=this,o,n
var $async$aj=A.aN(function(b,c){if(b===1)return A.aI(c,r)
for(;;)switch(s){case 0:s=3
return A.R(A.bP(A.B(A.B(v.G.WebAssembly).instantiateStreaming(a,p.cF())),t.m),$async$aj)
case 3:o=c
n=A.B(A.B(o.instance).exports)
if("_initialize" in n)t.g.a(n._initialize).call()
q=A.B(o.instance)
s=1
break
case 1:return A.aJ(q,r)}})
return A.aK($async$aj,r)}}
A.fa.prototype={
$0(){var s=this.a.a,r=A.B(v.G.Object),q=A.B(r.create.apply(r,[null]))
q.error_log=A.bH(s.gdf())
q.localtime=A.af(s.gdd())
q.xOpen=A.i0(s.gdR())
q.xDelete=A.fT(s.gdF())
q.xAccess=A.bI(s.gdv())
q.xFullPathname=A.bI(s.gdN())
q.xRandomness=A.fT(s.gdT())
q.xSleep=A.af(s.gdZ())
q.xCurrentTimeInt64=A.af(s.gdD())
q.xClose=A.bH(s.gdB())
q.xRead=A.bI(s.gdV())
q.xWrite=A.bI(s.ge6())
q.xTruncate=A.af(s.ge2())
q.xSync=A.af(s.ge0())
q.xFileSize=A.af(s.gdL())
q.xLock=A.af(s.gdP())
q.xUnlock=A.af(s.ge4())
q.xCheckReservedLock=A.af(s.gdz())
q.xDeviceCharacteristics=A.bH(s.gdH())
q.xFileControl=A.fT(s.gdJ())
q.xSectorSize=A.bH(s.gdX())
q["dispatch_()v"]=A.bH(s.gcR())
q["dispatch_()i"]=A.bH(s.gcN())
q.dispatch_update=A.i0(s.gcP())
q.dispatch_xFunc=A.bI(s.gcX())
q.dispatch_xStep=A.bI(s.gd0())
q.dispatch_xInverse=A.bI(s.gcZ())
q.dispatch_xValue=A.af(s.gd2())
q.dispatch_xFinal=A.af(s.gcV())
q.dispatch_compare=A.i0(s.gcT())
q.dispatch_busy=A.af(s.gcL())
q.changeset_apply_filter=A.af(s.gcJ())
q.changeset_apply_conflict=A.fT(s.gcH())
return q},
$S:54}
A.dB.prototype={}
A.bu.prototype={
aH(){return"FileType."+this.b}}
A.cg.prototype={
M(){var s=this.d
if(s!=null)return s
throw A.d(A.at("VFS closed"))},
bU(a,b){var s=$.ht().j(0,a)
if(s==null)return this.e.d.a6(a)?1:0
else return this.M().bD(s)?1:0},
bX(a,b){var s=$.ht().j(0,a)
if(s==null){this.e.d.am(0,a)
return null}else this.M().aa(s,!1)},
bZ(a){return A.A(A.B(new v.G.URL(a,"file:///")).pathname)},
ao(a,b){var s,r,q=this,p=a.a
if(p==null)return q.e.ao(a,b)
s=$.ht().j(0,p)
if(s==null)return q.e.ao(a,b)
r=q.M()
if(!r.bD(s))if((b&4)!==0){r.X(s).truncate(0)
r.aa(s,!0)}else throw A.d(B.aC)
return new A.bF(new A.dY(q,s,(b&8)!==0),0)},
c0(a){},
a4(a,b){var s=0,r=A.aM(t.H),q=this,p,o,n,m,l,k
var $async$a4=A.aN(function(c,d){if(c===1)return A.aI(d,r)
for(;;)switch(s){case 0:m=new A.eT(a,!1)
s=2
return A.R(m.$1("meta"),$async$a4)
case 2:l=d
k=A.c(l.getSize())
l.truncate(2)
s=3
return A.R(m.$1("database"),$async$a4)
case 3:p=d
s=4
return A.R(m.$1("journal"),$async$a4)
case 4:o=d
n=q.d=new A.fB(new Uint8Array(2),l,p,o)
if(k===0){n.aa(B.u,A.c(p.getSize())>0)
n.aa(B.v,A.c(o.getSize())>0)}return A.aJ(null,r)}})
return A.aK($async$a4,r)}}
A.eT.prototype={
$1(a){var s=0,r=A.aM(t.m),q,p=this,o,n,m
var $async$$1=A.aN(function(b,c){if(b===1)return A.aI(c,r)
for(;;)switch(s){case 0:o=t.m
m=A
s=3
return A.R(A.bP(A.B(p.a.getFileHandle(a,{create:!0})),o),$async$$1)
case 3:n=m.B(c.createSyncAccessHandle())
s=4
return A.R(A.bP(n,o),$async$$1)
case 4:q=c
s=1
break
case 1:return A.aJ(q,r)}})
return A.aK($async$$1,r)},
$S:55}
A.dY.prototype={
bL(a,b){return A.iA(this.a.M().X(this.b),a,{at:b})},
bV(){return this.d>=2?1:0},
bW(){var s=this.a,r=this.b
s.M().X(r).flush()
if(this.c)s.M().aa(r,!1)},
bY(){return A.c(this.a.M().X(this.b).getSize())},
c_(a){this.d=a},
c1(a){this.a.M().X(this.b).flush()},
c2(a){this.a.M().X(this.b).truncate(a)},
c3(a){this.d=a},
c4(a,b){if(A.iB(this.a.M().X(this.b),a,{at:b})<a.length)throw A.d(B.aE)}}
A.fB.prototype={
bD(a){var s,r=this.a
A.iA(this.b,r,{at:0})
s=a.a
if(!(s<r.length))return A.b(r,s)
return r[s]!==0},
aa(a,b){var s=this.a,r=a.a,q=b?1:0
s.$flags&2&&A.l(s)
if(!(r<s.length))return A.b(s,r)
s[r]=q
A.iB(this.b,s,{at:0})},
X(a){var s
switch(a.a){case 0:s=this.c
break
case 1:s=this.d
break
default:s=null}return s}}
A.f4.prototype={
c9(a,b){var s=this,r=s.c
r.a!==$&&A.jS()
r.a=s
r=t.S
A.fo(new A.f5(s),r)
A.fo(new A.f6(s),r)
s.r=A.fo(new A.f7(s),r)
s.w=A.fo(new A.f8(s),r)},
V(a,b){var s,r,q
t.L.a(a)
s=J.cL(a)
r=A.c(this.d.dart_sqlite3_malloc(s.gk(a)+b))
q=A.ar(t.a.a(this.b.buffer),0,null)
B.e.T(q,r,r+s.gk(a),a)
B.e.bE(q,r+s.gk(a),r+s.gk(a)+b,0)
return r},
a2(a){return this.V(a,0)}}
A.f5.prototype={
$1(a){return A.c(this.a.d.sqlite3changeset_finalize(A.c(a)))},
$S:1}
A.f6.prototype={
$1(a){return this.a.d.sqlite3session_delete(A.c(a))},
$S:1}
A.f7.prototype={
$1(a){return A.c(this.a.d.sqlite3_close_v2(A.c(a)))},
$S:1}
A.f8.prototype={
$1(a){return A.c(this.a.d.sqlite3_finalize(A.c(a)))},
$S:1}
A.aG.prototype={
gk(a){return this.b},
j(a,b){var s
if(b>=this.b)throw A.d(A.iD(b,this))
s=this.a
if(!(b>=0&&b<s.length))return A.b(s,b)
return s[b]},
A(a,b,c){var s=this
A.S(s).h("aG.E").a(c)
if(b>=s.b)throw A.d(A.iD(b,s))
B.e.A(s.a,b,c)},
sk(a,b){var s,r,q,p,o=this,n=o.b
if(b<n)for(s=o.a,r=s.$flags|0,q=b;q<n;++q){r&2&&A.l(s)
if(!(q>=0&&q<s.length))return A.b(s,q)
s[q]=0}else{n=o.a.length
if(b>n){if(n===0)p=new Uint8Array(b)
else p=o.cj(b)
B.e.T(p,0,o.b,o.a)
o.a=p}}o.b=b},
cj(a){var s=this.a.length*2
if(a!=null&&s<a)s=a
else if(s<8)s=8
return new Uint8Array(s)},
L(a,b,c,d,e){var s
A.S(this).h("f<aG.E>").a(d)
s=this.b
if(c>s)throw A.d(A.P(c,0,s,null,null))
B.e.L(this.a,b,c,d,e)},
T(a,b,c,d){return this.L(0,b,c,d,0)}}
A.dP.prototype={}
A.bf.prototype={};(function aliases(){var s=J.aT.prototype
s.c8=s.i
s=A.k.prototype
s.b9=s.L})();(function installTearOffs(){var s=hunkHelpers._static_1,r=hunkHelpers._static_0,q=hunkHelpers.installStaticTearOff,p=hunkHelpers._instance_1u,o=hunkHelpers._instance_2u,n=hunkHelpers.installInstanceTearOff
s(A,"mz","lg",4)
s(A,"mA","lh",4)
s(A,"mB","li",4)
r(A,"jE","mu",0)
q(A,"n6",1,null,["$2$parameter","$1"],["jQ",function(a){return A.jQ(a,!1)}],56,0)
s(A,"n5","mY",57)
s(A,"n3","kS",58)
s(A,"n4","kT",42)
s(A,"n2","kR",40)
var m
p(m=A.cX.prototype,"gdf","dg",1)
o(m,"gdd","de",34)
n(m,"gdR",0,5,null,["$5"],["dS"],35,0,0)
n(m,"gdF",0,3,null,["$3"],["dG"],36,0,0)
n(m,"gdv",0,4,null,["$4"],["dw"],18,0,0)
n(m,"gdN",0,4,null,["$4"],["dO"],18,0,0)
n(m,"gdT",0,3,null,["$3"],["dU"],38,0,0)
o(m,"gdZ","e_",19)
o(m,"gdD","dE",19)
p(m,"gdB","dC",7)
n(m,"gdV",0,4,null,["$4"],["dW"],20,0,0)
n(m,"ge6",0,4,null,["$4"],["e7"],20,0,0)
o(m,"ge2","e3",59)
o(m,"ge0","e1",2)
o(m,"gdL","dM",2)
o(m,"gdP","dQ",2)
o(m,"ge4","e5",2)
o(m,"gdz","dA",2)
p(m,"gdH","dI",7)
n(m,"gdJ",0,3,null,["$3"],["dK"],44,0,0)
p(m,"gdX","dY",7)
p(m,"gcR","cS",4)
p(m,"gcN","cO",46)
n(m,"gcP",0,5,null,["$5"],["cQ"],47,0,0)
n(m,"gcX",0,4,null,["$4"],["cY"],5,0,0)
n(m,"gd0",0,4,null,["$4"],["d1"],5,0,0)
n(m,"gcZ",0,4,null,["$4"],["d_"],5,0,0)
o(m,"gd2","d3",10)
o(m,"gcV","cW",10)
n(m,"gcT",0,5,null,["$5"],["cU"],50,0,0)
o(m,"gcL","cM",51)
o(m,"gcJ","cK",52)
n(m,"gcH",0,3,null,["$3"],["cI"],53,0,0)})();(function inheritance(){var s=hunkHelpers.mixin,r=hunkHelpers.inherit,q=hunkHelpers.inheritMany
r(A.e,null)
q(A.e,[A.hC,J.d3,A.cf,J.bR,A.q,A.eP,A.f,A.b9,A.c6,A.bh,A.ch,A.T,A.aH,A.bT,A.f_,A.eF,A.bY,A.cA,A.aP,A.a_,A.ez,A.c4,A.b8,A.d7,A.fA,A.fk,A.fJ,A.al,A.dN,A.fH,A.fF,A.dF,A.ad,A.dI,A.bj,A.F,A.dG,A.dZ,A.cG,A.k,A.bS,A.cW,A.fM,A.cF,A.z,A.ct,A.a3,A.aR,A.fm,A.dk,A.cl,A.fn,A.v,A.d2,A.M,A.e_,A.cm,A.d0,A.eE,A.dQ,A.dj,A.dx,A.eV,A.cj,A.fO,A.eZ,A.dJ,A.bi,A.dL,A.bD,A.dK,A.dR,A.ci,A.hy,A.a0,A.az,A.ap,A.aj,A.aq,A.ck,A.ao,A.b5,A.cY,A.eX,A.cU,A.bs,A.H,A.cQ,A.dW,A.dS,A.b7,A.aZ,A.eW,A.dC,A.dA,A.fc,A.dD,A.b_,A.au,A.cX,A.a7,A.f9,A.fB,A.f4])
q(J.d3,[J.d5,J.c1,J.c2,J.U,J.bw,J.bv,J.aS])
q(J.c2,[J.aT,J.r,A.aU,A.c9])
q(J.aT,[J.dl,J.bg,J.aB])
r(J.d4,A.cf)
r(J.ey,J.r)
q(J.bv,[J.c0,J.d6])
q(A.q,[A.bx,A.aE,A.d8,A.dw,A.dr,A.dM,A.cO,A.ah,A.co,A.dv,A.be,A.cV])
q(A.f,[A.i,A.bb,A.cp,A.bd])
q(A.i,[A.V,A.c5,A.eA])
q(A.V,[A.cn,A.a5,A.ce])
r(A.bV,A.bb)
r(A.bW,A.bd)
r(A.b0,A.aH)
q(A.b0,[A.cy,A.bF,A.cz])
r(A.bU,A.bT)
r(A.cb,A.aE)
q(A.aP,[A.cS,A.cT,A.du,A.hf,A.hh,A.fe,A.fd,A.fP,A.fx,A.fE,A.fj,A.hl,A.hm,A.ho,A.hn,A.fU,A.fV,A.fW,A.fX,A.fZ,A.h4,A.h_,A.h0,A.h2,A.h1,A.hp,A.hq,A.eY,A.eq,A.es,A.eo,A.en,A.el,A.hk,A.eT,A.f5,A.f6,A.f7,A.f8])
q(A.du,[A.dt,A.br])
r(A.c3,A.a_)
q(A.cT,[A.hg,A.fQ,A.h7,A.fy,A.eD,A.fi,A.fY,A.h3,A.er,A.em,A.et])
r(A.by,A.aU)
q(A.c9,[A.c7,A.L])
q(A.L,[A.cu,A.cw])
r(A.cv,A.cu)
r(A.c8,A.cv)
r(A.cx,A.cw)
r(A.a6,A.cx)
q(A.c8,[A.dc,A.dd])
q(A.a6,[A.de,A.df,A.dg,A.dh,A.di,A.ca,A.bc])
r(A.bG,A.dM)
q(A.cS,[A.ff,A.fg,A.fG,A.fp,A.ft,A.fs,A.fr,A.fq,A.fw,A.fv,A.fu,A.fD,A.h6,A.fL,A.fK,A.eu,A.ep,A.ek,A.ej,A.e8,A.e5,A.ea,A.ec,A.ee,A.e7,A.ed,A.ei,A.eg,A.ef,A.e9,A.eb,A.eh,A.e6,A.fa])
r(A.cq,A.dI)
r(A.dV,A.cG)
r(A.d_,A.bS)
r(A.dy,A.d_)
r(A.f2,A.cW)
q(A.ah,[A.aC,A.bZ])
q(A.fm,[A.aA,A.eH,A.bu])
q(A.k,[A.dz,A.bC,A.aG])
r(A.bB,A.cU)
q(A.bs,[A.c_,A.dT])
r(A.dE,A.c_)
r(A.cR,A.H)
q(A.cR,[A.d1,A.cg])
q(A.cQ,[A.dO,A.dY])
r(A.dU,A.dT)
r(A.dq,A.dU)
r(A.dX,A.dW)
r(A.N,A.dX)
r(A.dB,A.eX)
r(A.dP,A.aG)
r(A.bf,A.dP)
s(A.cu,A.k)
s(A.cv,A.T)
s(A.cw,A.k)
s(A.cx,A.T)
s(A.dT,A.k)
s(A.dU,A.dj)
s(A.dW,A.dx)
s(A.dX,A.a_)})()
var v={G:typeof self!="undefined"?self:globalThis,typeUniverse:{eC:new Map(),tR:{},eT:{},tPV:{},sEA:[]},mangledGlobalNames:{a:"int",m:"double",a2:"num",h:"String",aO:"bool",M:"Null",j:"List",e:"Object",ba:"Map",p:"JSObject"},mangledNames:{},types:["~()","~(a)","a(X,a)","h?(as)","~(~())","~(a7,a,a,a)","~(@)","a(X)","~(aD,j<cc>)","~(aD)","~(a7,a)","@()","e?(as)","M(@)","M()","~(as)","a(h?,h?)","e?()","a(H,a,a,a)","a(H,a)","a(X,a,a,U)","r<e?>(j<e?>)","~(e?,e?)","~(h,0^?(h))<t<0^>>","a3?(h)","h(h)","a(a,a)","h(e?)","a(a)","0&()","M(p)","ai<~>(~)","aO(h)","@(@,h)","~(U,a)","X?(H,a,a,a,a)","a(H,a,a)","M(~())","a(H?,a,a)","a(as)","aq?(h)","@(@)","aj?(h)","@(h)","a(X,a,a)","M(@,aW)","a(a())","~(~(a,h,a),a,a,a,U)","~(a,@)","e(e,h,a)","a(a7,a,a,a,a)","a(a(a),a)","a(eQ,a)","a(eQ,a,a)","p()","ai<p>(h)","e?(e?{parameter:aO})","e?(e?)","ap?(h)","a(X,U)","M(e,aW)"],interceptorsByTag:null,leafTags:null,arrayRti:Symbol("$ti"),rttc:{"2;":(a,b)=>c=>c instanceof A.cy&&a.b(c.a)&&b.b(c.b),"2;file,outFlags":(a,b)=>c=>c instanceof A.bF&&a.b(c.a)&&b.b(c.b),"2;result,resultCode":(a,b)=>c=>c instanceof A.cz&&a.b(c.a)&&b.b(c.b)}}
A.lG(v.typeUniverse,JSON.parse('{"aB":"aT","dl":"aT","bg":"aT","nk":"aU","r":{"j":["1"],"i":["1"],"p":[],"f":["1"]},"d5":{"aO":[],"o":[]},"c1":{"o":[]},"c2":{"p":[]},"aT":{"p":[]},"d4":{"cf":[]},"ey":{"r":["1"],"j":["1"],"i":["1"],"p":[],"f":["1"]},"bR":{"K":["1"]},"bv":{"m":[],"a2":[],"t":["a2"]},"c0":{"m":[],"a":[],"a2":[],"t":["a2"],"o":[]},"d6":{"m":[],"a2":[],"t":["a2"],"o":[]},"aS":{"h":[],"t":["h"],"eI":[],"o":[]},"bx":{"q":[]},"i":{"f":["1"]},"V":{"i":["1"],"f":["1"]},"cn":{"V":["1"],"i":["1"],"f":["1"],"V.E":"1","f.E":"1"},"b9":{"K":["1"]},"bb":{"f":["2"],"f.E":"2"},"bV":{"bb":["1","2"],"i":["2"],"f":["2"],"f.E":"2"},"c6":{"K":["2"]},"a5":{"V":["2"],"i":["2"],"f":["2"],"V.E":"2","f.E":"2"},"cp":{"f":["1"],"f.E":"1"},"bh":{"K":["1"]},"bd":{"f":["1"],"f.E":"1"},"bW":{"bd":["1"],"i":["1"],"f":["1"],"f.E":"1"},"ch":{"K":["1"]},"ce":{"V":["1"],"i":["1"],"f":["1"],"V.E":"1","f.E":"1"},"cy":{"b0":[],"aH":[]},"bF":{"b0":[],"aH":[]},"cz":{"b0":[],"aH":[]},"bT":{"ba":["1","2"]},"bU":{"bT":["1","2"],"ba":["1","2"]},"cb":{"aE":[],"q":[]},"d8":{"q":[]},"dw":{"q":[]},"cA":{"aW":[]},"aP":{"b6":[]},"cS":{"b6":[]},"cT":{"b6":[]},"du":{"b6":[]},"dt":{"b6":[]},"br":{"b6":[]},"dr":{"q":[]},"c3":{"a_":["1","2"],"ba":["1","2"],"a_.K":"1","a_.V":"2"},"c5":{"i":["1"],"f":["1"],"f.E":"1"},"c4":{"K":["1"]},"eA":{"i":["1"],"f":["1"],"f.E":"1"},"b8":{"K":["1"]},"b0":{"aH":[]},"d7":{"l4":[],"eI":[]},"by":{"aU":[],"p":[],"o":[]},"aU":{"p":[],"o":[]},"c9":{"p":[]},"c7":{"ir":[],"p":[],"o":[]},"L":{"a4":["1"],"p":[]},"c8":{"k":["m"],"L":["m"],"j":["m"],"a4":["m"],"i":["m"],"p":[],"f":["m"],"T":["m"]},"a6":{"k":["a"],"L":["a"],"j":["a"],"a4":["a"],"i":["a"],"p":[],"f":["a"],"T":["a"]},"dc":{"k":["m"],"y":["m"],"L":["m"],"j":["m"],"a4":["m"],"i":["m"],"p":[],"f":["m"],"T":["m"],"o":[],"k.E":"m"},"dd":{"k":["m"],"y":["m"],"L":["m"],"j":["m"],"a4":["m"],"i":["m"],"p":[],"f":["m"],"T":["m"],"o":[],"k.E":"m"},"de":{"a6":[],"k":["a"],"y":["a"],"L":["a"],"j":["a"],"a4":["a"],"i":["a"],"p":[],"f":["a"],"T":["a"],"o":[],"k.E":"a"},"df":{"a6":[],"k":["a"],"y":["a"],"L":["a"],"j":["a"],"a4":["a"],"i":["a"],"p":[],"f":["a"],"T":["a"],"o":[],"k.E":"a"},"dg":{"a6":[],"k":["a"],"y":["a"],"L":["a"],"j":["a"],"a4":["a"],"i":["a"],"p":[],"f":["a"],"T":["a"],"o":[],"k.E":"a"},"dh":{"a6":[],"hM":[],"k":["a"],"y":["a"],"L":["a"],"j":["a"],"a4":["a"],"i":["a"],"p":[],"f":["a"],"T":["a"],"o":[],"k.E":"a"},"di":{"a6":[],"k":["a"],"y":["a"],"L":["a"],"j":["a"],"a4":["a"],"i":["a"],"p":[],"f":["a"],"T":["a"],"o":[],"k.E":"a"},"ca":{"a6":[],"k":["a"],"y":["a"],"L":["a"],"j":["a"],"a4":["a"],"i":["a"],"p":[],"f":["a"],"T":["a"],"o":[],"k.E":"a"},"bc":{"a6":[],"f1":[],"k":["a"],"y":["a"],"L":["a"],"j":["a"],"a4":["a"],"i":["a"],"p":[],"f":["a"],"T":["a"],"o":[],"k.E":"a"},"dM":{"q":[]},"bG":{"aE":[],"q":[]},"ad":{"q":[]},"cq":{"dI":["1"]},"F":{"ai":["1"]},"cG":{"j0":[]},"dV":{"cG":[],"j0":[]},"k":{"j":["1"],"i":["1"],"f":["1"]},"a_":{"ba":["1","2"]},"d_":{"bS":["h","j<a>"]},"dy":{"bS":["h","j<a>"]},"e4":{"t":["e4"]},"a3":{"t":["a3"]},"m":{"a2":[],"t":["a2"]},"aR":{"t":["aR"]},"a":{"a2":[],"t":["a2"]},"j":{"i":["1"],"f":["1"]},"a2":{"t":["a2"]},"h":{"t":["h"],"eI":[]},"z":{"e4":[],"t":["e4"]},"ct":{"kE":["1"]},"cO":{"q":[]},"aE":{"q":[]},"ah":{"q":[]},"aC":{"q":[]},"bZ":{"aC":[],"q":[]},"co":{"q":[]},"dv":{"q":[]},"be":{"q":[]},"cV":{"q":[]},"dk":{"q":[]},"cl":{"q":[]},"d2":{"q":[]},"e_":{"aW":[]},"dQ":{"l_":[]},"dL":{"e3":["bi"]},"dK":{"e3":["bD"]},"az":{"t":["az"]},"ap":{"t":["ap"]},"aj":{"t":["aj"]},"aq":{"t":["aq"]},"as":{"j":["e?"],"i":["e?"],"f":["e?"]},"cY":{"kz":[]},"dz":{"k":["e?"],"as":[],"j":["e?"],"i":["e?"],"f":["e?"],"k.E":"e?"},"bB":{"cU":[]},"dE":{"c_":[],"bs":[],"K":["N"]},"d1":{"H":[]},"dO":{"X":[]},"N":{"dx":["h","@"],"a_":["h","@"],"ba":["h","@"],"a_.K":"h","a_.V":"@"},"c_":{"bs":[],"K":["N"]},"dq":{"k":["N"],"dj":["N"],"j":["N"],"i":["N"],"bs":[],"f":["N"],"k.E":"N"},"dS":{"K":["N"]},"b7":{"l9":[]},"cR":{"H":[]},"cQ":{"X":[]},"au":{"cc":[]},"dC":{"l0":[]},"dA":{"l1":[]},"dD":{"l2":[]},"b_":{"aD":[]},"bC":{"k":["au"],"j":["au"],"i":["au"],"f":["au"],"k.E":"au"},"cg":{"H":[]},"dY":{"X":[]},"bf":{"aG":["a"],"k":["a"],"j":["a"],"i":["a"],"f":["a"],"k.E":"a","aG.E":"a"},"aG":{"k":["1"],"j":["1"],"i":["1"],"f":["1"]},"dP":{"aG":["a"],"k":["a"],"j":["a"],"i":["a"],"f":["a"]},"kK":{"y":["a"],"j":["a"],"i":["a"],"f":["a"]},"f1":{"y":["a"],"j":["a"],"i":["a"],"f":["a"]},"ld":{"y":["a"],"j":["a"],"i":["a"],"f":["a"]},"kI":{"y":["a"],"j":["a"],"i":["a"],"f":["a"]},"hM":{"y":["a"],"j":["a"],"i":["a"],"f":["a"]},"kJ":{"y":["a"],"j":["a"],"i":["a"],"f":["a"]},"lc":{"y":["a"],"j":["a"],"i":["a"],"f":["a"]},"kF":{"y":["m"],"j":["m"],"i":["m"],"f":["m"]},"kG":{"y":["m"],"j":["m"],"i":["m"],"f":["m"]}}'))
A.lF(v.typeUniverse,JSON.parse('{"L":1,"cW":2}'))
var u={c:"Error handler must accept one Object or one Object and a StackTrace as arguments, and return a value of the returned future's type"}
var t=(function rtii(){var s=A.b2
return{_:s("ao<bD>"),y:s("ao<bi>"),E:s("ao<e?>"),n:s("ad"),q:s("t<@>"),k:s("a3"),U:s("az"),J:s("aR"),O:s("i<@>"),Q:s("q"),Z:s("b6"),bM:s("f<m>"),hf:s("f<@>"),Y:s("f<a>"),D:s("r<j<e?>>"),f:s("r<e>"),bb:s("r<bB>"),s:s("r<h>"),eQ:s("r<m>"),gn:s("r<@>"),c:s("r<e?>"),T:s("c1"),m:s("p"),C:s("U"),g:s("aB"),aU:s("a4<@>"),w:s("j<cc>"),dy:s("j<h>"),b:s("j<@>"),L:s("j<a>"),W:s("j<e?>"),A:s("ap"),B:s("aq"),t:s("aj"),a:s("by"),eB:s("a6"),bm:s("bc"),P:s("M"),K:s("e"),G:s("aC"),gT:s("nm"),bQ:s("+()"),cf:s("+(p?,p)"),u:s("+(e?,a)"),V:s("a7"),bJ:s("ce<h>"),fI:s("N"),p:s("eQ"),h:s("cg"),l:s("aW"),N:s("h"),dm:s("o"),eK:s("aE"),I:s("f1"),ak:s("bg"),j:s("H"),r:s("X"),ab:s("dB"),gV:s("au"),cc:s("cp<h>"),gB:s("bD"),cl:s("z"),al:s("dJ"),aW:s("bi"),d:s("F<@>"),cd:s("F<~>"),v:s("aO"),bO:s("aO(e)"),bB:s("aO(h)"),i:s("m"),z:s("@"),fO:s("@()"),x:s("@(e)"),R:s("@(e,aW)"),S:s("a"),ez:s("a()"),aa:s("a(h?,h?)"),f5:s("a(a)"),eH:s("ai<M>?"),an:s("p?"),X:s("e?"),e:s("e?(as)"),dk:s("h?"),fN:s("bf?"),bx:s("H?"),F:s("bj<@,@>?"),fQ:s("aO?"),cD:s("m?"),h6:s("a?"),cg:s("a2?"),cN:s("~(aD,j<cc>)?"),ci:s("~(aD)?"),o:s("a2"),H:s("~"),M:s("~()"),bN:s("~(aD,j<cc>)"),fB:s("~(aD)"),hd:s("~(a,h,a)")}})();(function constants(){var s=hunkHelpers.makeConstList
B.a8=J.d3.prototype
B.b=J.r.prototype
B.a=J.c0.prototype
B.l=J.bv.prototype
B.c=J.aS.prototype
B.a9=J.aB.prototype
B.aa=J.c2.prototype
B.ae=A.c7.prototype
B.e=A.bc.prototype
B.A=J.dl.prototype
B.n=J.bg.prototype
B.o=new A.b5(1)
B.B=new A.b5(2)
B.j=new A.b5(3)
B.C=new A.b5(4)
B.aF=new A.b5(-1)
B.m=new A.d2()
B.p=function getTagFallback(o) {
  var s = Object.prototype.toString.call(o);
  return s.substring(8, s.length - 1);
}
B.D=function() {
  var toStringFunction = Object.prototype.toString;
  function getTag(o) {
    var s = toStringFunction.call(o);
    return s.substring(8, s.length - 1);
  }
  function getUnknownTag(object, tag) {
    if (/^HTML[A-Z].*Element$/.test(tag)) {
      var name = toStringFunction.call(object);
      if (name == "[object Object]") return null;
      return "HTMLElement";
    }
  }
  function getUnknownTagGenericBrowser(object, tag) {
    if (object instanceof HTMLElement) return "HTMLElement";
    return getUnknownTag(object, tag);
  }
  function prototypeForTag(tag) {
    if (typeof window == "undefined") return null;
    if (typeof window[tag] == "undefined") return null;
    var constructor = window[tag];
    if (typeof constructor != "function") return null;
    return constructor.prototype;
  }
  function discriminator(tag) { return null; }
  var isBrowser = typeof HTMLElement == "function";
  return {
    getTag: getTag,
    getUnknownTag: isBrowser ? getUnknownTagGenericBrowser : getUnknownTag,
    prototypeForTag: prototypeForTag,
    discriminator: discriminator };
}
B.I=function(getTagFallback) {
  return function(hooks) {
    if (typeof navigator != "object") return hooks;
    var userAgent = navigator.userAgent;
    if (typeof userAgent != "string") return hooks;
    if (userAgent.indexOf("DumpRenderTree") >= 0) return hooks;
    if (userAgent.indexOf("Chrome") >= 0) {
      function confirm(p) {
        return typeof window == "object" && window[p] && window[p].name == p;
      }
      if (confirm("Window") && confirm("HTMLElement")) return hooks;
    }
    hooks.getTag = getTagFallback;
  };
}
B.E=function(hooks) {
  if (typeof dartExperimentalFixupGetTag != "function") return hooks;
  hooks.getTag = dartExperimentalFixupGetTag(hooks.getTag);
}
B.H=function(hooks) {
  if (typeof navigator != "object") return hooks;
  var userAgent = navigator.userAgent;
  if (typeof userAgent != "string") return hooks;
  if (userAgent.indexOf("Firefox") == -1) return hooks;
  var getTag = hooks.getTag;
  var quickMap = {
    "BeforeUnloadEvent": "Event",
    "DataTransfer": "Clipboard",
    "GeoGeolocation": "Geolocation",
    "Location": "!Location",
    "WorkerMessageEvent": "MessageEvent",
    "XMLDocument": "!Document"};
  function getTagFirefox(o) {
    var tag = getTag(o);
    return quickMap[tag] || tag;
  }
  hooks.getTag = getTagFirefox;
}
B.G=function(hooks) {
  if (typeof navigator != "object") return hooks;
  var userAgent = navigator.userAgent;
  if (typeof userAgent != "string") return hooks;
  if (userAgent.indexOf("Trident/") == -1) return hooks;
  var getTag = hooks.getTag;
  var quickMap = {
    "BeforeUnloadEvent": "Event",
    "DataTransfer": "Clipboard",
    "HTMLDDElement": "HTMLElement",
    "HTMLDTElement": "HTMLElement",
    "HTMLPhraseElement": "HTMLElement",
    "Position": "Geoposition"
  };
  function getTagIE(o) {
    var tag = getTag(o);
    var newTag = quickMap[tag];
    if (newTag) return newTag;
    if (tag == "Object") {
      if (window.DataView && (o instanceof window.DataView)) return "DataView";
    }
    return tag;
  }
  function prototypeForTagIE(tag) {
    var constructor = window[tag];
    if (constructor == null) return null;
    return constructor.prototype;
  }
  hooks.getTag = getTagIE;
  hooks.prototypeForTag = prototypeForTagIE;
}
B.F=function(hooks) {
  var getTag = hooks.getTag;
  var prototypeForTag = hooks.prototypeForTag;
  function getTagFixed(o) {
    var tag = getTag(o);
    if (tag == "Document") {
      if (!!o.xmlVersion) return "!Document";
      return "!HTMLDocument";
    }
    return tag;
  }
  function prototypeForTagFixed(tag) {
    if (tag == "Document") return null;
    return prototypeForTag(tag);
  }
  hooks.getTag = getTagFixed;
  hooks.prototypeForTag = prototypeForTagFixed;
}
B.q=function(hooks) { return hooks; }

B.J=new A.dk()
B.f=new A.eP()
B.r=new A.dy()
B.h=new A.f2()
B.K=new A.dK()
B.L=new A.dL()
B.d=new A.dV()
B.k=new A.e_()
B.M=new A.aA(0,"exact")
B.t=new A.aA(4,"halfAwayFromZero")
B.R=new A.aR(0)
B.u=new A.bu("/database",0,"database")
B.v=new A.bu("/database-journal",1,"journal")
B.S=new A.v("Invalid timestamp components.",null,null)
B.T=new A.v("Invalid calendar date in instant.",null,null)
B.U=new A.v("Expected a local date and time without a timezone.",null,null)
B.V=new A.v("BC requires a positive era year.",null,null)
B.W=new A.v("Decimal result requires rounding.",null,null)
B.X=new A.v("Expected a finite decimal string.",null,null)
B.Y=new A.v("Expected a Gregorian date without a timezone.",null,null)
B.Z=new A.v("Expected a time without a timezone, with at most six fractional digits.",null,null)
B.a_=new A.v("Expected a timestamp with at most six fractional digits.",null,null)
B.a0=new A.v("Invalid UTC offset.",null,null)
B.w=new A.v("Instant exceeds the common DateTime/PostgreSQL range.",null,null)
B.a1=new A.v("Expected a local time or time text.",null,null)
B.a2=new A.v("Decimal input is too long.",null,null)
B.a3=new A.v("BC dates require a positive era year.",null,null)
B.a4=new A.v("Expected a UTC instant or timestamp text.",null,null)
B.a5=new A.v("Expected a local timestamp or timestamp text.",null,null)
B.a6=new A.v("Decimal exponent is out of range.",null,null)
B.a7=new A.v("Exact decimal storage requires text or an integer.",null,null)
B.N=new A.aA(1,"towardZero")
B.O=new A.aA(2,"floor")
B.P=new A.aA(3,"ceiling")
B.Q=new A.aA(5,"halfEven")
B.i=s([B.M,B.N,B.O,B.P,B.t,B.Q],A.b2("r<aA>"))
B.x=s([1e6,1e5,1e4,1000,100,10,1],A.b2("r<a>"))
B.ab=s([],t.D)
B.ac=s([],t.s)
B.y=s([],t.c)
B.ad=s([B.u,B.v],A.b2("r<bu>"))
B.af={}
B.z=new A.bU(B.af,[],A.b2("bU<h,a>"))
B.aG=new A.eH(2,"readWriteCreate")
B.ag=new A.a0("DRIVER.OPEN","Worker is already open.")
B.ah=new A.a0("CURSOR.READ_ONLY","Streaming requires a read-only query.")
B.ai=new A.a0("CODEC.INTEGER","Browser int transport requires a safe integer; use BigInt for wider integers or SqlReal for floating values.")
B.aj=new A.a0("DRIVER.PROTOCOL","Invalid SQLite worker value.")
B.ak=new A.a0("CODEC.PARAMETER","Unsupported SQLite wire value.")
B.al=new A.a0("DRIVER.STORAGE","Unknown browser storage.")
B.am=new A.a0("DRIVER.CLOSED","SQLite worker is not open.")
B.an=new A.a0("DRIVER.FOREIGN_KEYS","SQLite foreign keys could not be enabled.")
B.ao=new A.a0("CURSOR.CLOSED","Cursor has ended.")
B.ap=new A.a0("DRIVER.PROTOCOL","Unknown SQLite worker command.")
B.aq=A.an("nb")
B.ar=A.an("ir")
B.as=A.an("kF")
B.at=A.an("kG")
B.au=A.an("kI")
B.av=A.an("kJ")
B.aw=A.an("kK")
B.ax=A.an("e")
B.ay=A.an("hM")
B.az=A.an("lc")
B.aA=A.an("ld")
B.aB=A.an("f1")
B.aC=new A.aZ(14)
B.aD=new A.aZ(522)
B.aE=new A.aZ(778)})();(function staticFields(){$.fz=null
$.a9=A.x([],t.f)
$.iR=null
$.ip=null
$.io=null
$.jH=null
$.jD=null
$.jL=null
$.hb=null
$.hi=null
$.i8=null
$.fC=A.x([],A.b2("r<j<e>?>"))
$.bK=null
$.cJ=null
$.cK=null
$.i2=!1
$.w=B.d
$.j3=null
$.j4=null
$.j5=null
$.j6=null
$.hP=A.fl("_lastQuoRemDigits")
$.hQ=A.fl("_lastQuoRemUsed")
$.cs=A.fl("_lastRemUsed")
$.hR=A.fl("_lastRem_nsh")})();(function lazyInitializers(){var s=hunkHelpers.lazyFinal,r=hunkHelpers.lazy
s($,"nd","jX",()=>A.hc("_$dart_dartClosure"))
s($,"nc","bQ",()=>A.hc("_$dart_dartClosure_dartJSInterop"))
s($,"nN","kj",()=>A.x([new J.d4()],A.b2("r<cf>")))
s($,"no","k2",()=>A.aF(A.f0({
toString:function(){return"$receiver$"}})))
s($,"np","k3",()=>A.aF(A.f0({$method$:null,
toString:function(){return"$receiver$"}})))
s($,"nq","k4",()=>A.aF(A.f0(null)))
s($,"nr","k5",()=>A.aF(function(){var $argumentsExpr$="$arguments$"
try{null.$method$($argumentsExpr$)}catch(q){return q.message}}()))
s($,"nu","k8",()=>A.aF(A.f0(void 0)))
s($,"nv","k9",()=>A.aF(function(){var $argumentsExpr$="$arguments$"
try{(void 0).$method$($argumentsExpr$)}catch(q){return q.message}}()))
s($,"nt","k7",()=>A.aF(A.iY(null)))
s($,"ns","k6",()=>A.aF(function(){try{null.$method$}catch(q){return q.message}}()))
s($,"nx","kb",()=>A.aF(A.iY(void 0)))
s($,"nw","ka",()=>A.aF(function(){try{(void 0).$method$}catch(q){return q.message}}()))
s($,"nz","id",()=>A.lf())
s($,"nK","kh",()=>A.iP(4096))
s($,"nI","kf",()=>new A.fL().$0())
s($,"nJ","kg",()=>new A.fK().$0())
s($,"nG","E",()=>A.cr(0))
s($,"nE","Z",()=>A.cr(1))
s($,"nF","ih",()=>A.cr(2))
s($,"nC","ig",()=>$.Z().D(0))
s($,"nA","ie",()=>A.cr(1e4))
r($,"nD","kd",()=>A.cd("^\\s*([+-]?)((0x[a-f0-9]+)|(\\d+)|([a-z0-9]+))\\s*$",!1))
s($,"nB","kc",()=>A.iP(8))
s($,"nH","ke",()=>typeof FinalizationRegistry=="function"?FinalizationRegistry:null)
s($,"nL","hu",()=>A.jJ(B.ax))
s($,"nl","k1",()=>{var q=new A.dQ(new DataView(new ArrayBuffer(A.lW(8))))
q.ca()
return q})
s($,"nf","ib",()=>A.kB($.E(),0))
s($,"ne","jY",()=>A.cd("^([+-]?)([0-9]*)(?:\\.([0-9]*))?(?:[eE]([+-]?[0-9]+))?$",!0))
s($,"nM","ki",()=>A.cd("^(-?\\d{4,7})-(\\d{2})-(\\d{2})[ T](\\d{2}:\\d{2}(?::\\d{2}(?:\\.\\d{1,6})?)?)(Z|[+-]\\d{2}(?::?\\d{2})?(?::?\\d{2})?)?( BC)?$",!1))
s($,"ni","k_",()=>A.cd("^(-?\\d{4,7})-(\\d{2})-(\\d{2})( BC)?$",!1))
s($,"nj","k0",()=>A.cd("^(\\d{2}):(\\d{2})(?::(\\d{2})(?:\\.(\\d{1,6}))?)?$",!0))
s($,"nh","jZ",()=>A.cd("^(-?\\d{4,7}-\\d{2}-\\d{2})[ T](\\d{2}:\\d{2}(?::\\d{2}(?:\\.\\d{1,6})?)?)( BC)?$",!1))
s($,"na","jW",()=>$.Z().O(0,63).D(0))
s($,"n9","jV",()=>{var q=$.Z()
return q.O(0,63).ac(0,q)})
s($,"n8","hs",()=>$.k1())
s($,"ny","ic",()=>new A.d0(new WeakMap(),A.b2("d0<a>")))
s($,"ng","ht",()=>{var q,p,o=A.d9(t.N,A.b2("bu"))
for(q=0;q<2;++q){p=B.ad[q]
o.A(0,p.c,p)}return o})})();(function nativeSupport(){!function(){var s=function(a){var m={}
m[a]=1
return Object.keys(hunkHelpers.convertToFastObject(m))[0]}
v.getIsolateTag=function(a){return s("___dart_"+a+v.isolateTag)}
var r="___dart_isolate_tags_"
var q=Object[r]||(Object[r]=Object.create(null))
var p="_ZxYxX"
for(var o=0;;o++){var n=s(p+"_"+o+"_")
if(!(n in q)){q[n]=1
v.isolateTag=n
break}}v.dispatchPropertyName=v.getIsolateTag("dispatch_record")}()
hunkHelpers.setOrUpdateInterceptorsByTag({SharedArrayBuffer:A.aU,ArrayBuffer:A.by,ArrayBufferView:A.c9,DataView:A.c7,Float32Array:A.dc,Float64Array:A.dd,Int16Array:A.de,Int32Array:A.df,Int8Array:A.dg,Uint16Array:A.dh,Uint32Array:A.di,Uint8ClampedArray:A.ca,CanvasPixelArray:A.ca,Uint8Array:A.bc})
hunkHelpers.setOrUpdateLeafTags({SharedArrayBuffer:true,ArrayBuffer:true,ArrayBufferView:false,DataView:true,Float32Array:true,Float64Array:true,Int16Array:true,Int32Array:true,Int8Array:true,Uint16Array:true,Uint32Array:true,Uint8ClampedArray:true,CanvasPixelArray:true,Uint8Array:false})
A.L.$nativeSuperclassTag="ArrayBufferView"
A.cu.$nativeSuperclassTag="ArrayBufferView"
A.cv.$nativeSuperclassTag="ArrayBufferView"
A.c8.$nativeSuperclassTag="ArrayBufferView"
A.cw.$nativeSuperclassTag="ArrayBufferView"
A.cx.$nativeSuperclassTag="ArrayBufferView"
A.a6.$nativeSuperclassTag="ArrayBufferView"})()
Function.prototype.$1=function(a){return this(a)}
Function.prototype.$2=function(a,b){return this(a,b)}
Function.prototype.$0=function(){return this()}
Function.prototype.$1$1=function(a){return this(a)}
Function.prototype.$3=function(a,b,c){return this(a,b,c)}
Function.prototype.$4=function(a,b,c,d){return this(a,b,c,d)}
Function.prototype.$1$2=function(a,b){return this(a,b)}
Function.prototype.$5=function(a,b,c,d,e){return this(a,b,c,d,e)}
convertAllToFastObject(w)
convertToFastObject($);(function(a){if(typeof document==="undefined"){a(null)
return}if(typeof document.currentScript!="undefined"){a(document.currentScript)
return}var s=document.scripts
function onLoad(b){for(var q=0;q<s.length;++q){s[q].removeEventListener("load",onLoad,false)}a(b.target)}for(var r=0;r<s.length;++r){s[r].addEventListener("load",onLoad,false)}})(function(a){v.currentScript=a
var s=A.mT
if(typeof dartMainRunner==="function"){dartMainRunner(s,[])}else{s([])}})})()