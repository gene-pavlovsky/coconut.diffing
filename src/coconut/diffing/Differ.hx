package coconut.diffing;

import coconut.diffing.Rendered;

class Differ<Virtual, Real> {

  function _renderAll(
    nodes:Array<VNode<Virtual, Real>>, 
    with:{ 
      function native(type:NodeType, key:Key, v:Virtual):Real; 
      function widget<A>(type:NodeType, key:Key, attr:A, t:WidgetType<Virtual, A, Real>):Widget<Virtual, Real>; 
    }
  ):Rendered<Virtual, Real> {

    var byType = new Map<NodeType, TypeRegistry<RNode<Virtual, Real>>>(),
        childList = [];

    for (n in nodes) {
      var registry = switch byType[n.type] {
        case null: byType[n.type] = new TypeRegistry();
        case v: v;
      }
      function add(r:Dynamic, kind) {
        
        if (n.ref != null)
          n.ref(r);//TODO: schedule ref rather than calling directly

        var n:RNode<Virtual, Real> = {
          key: n.key,
          type: n.type,
          ref: n.ref,
          kind: kind
        }

        registry.put(n);
        childList.push(n);
      }
      switch n.kind {
        case VNative(v):

          var r = with.native(n.type, n.key, v);
          
          add(r, RNative(v, r));
        case VWidget(a, t):

          var w = with.widget(n.type, n.key, a, t);

          add(w, RWidget(w));
      }
    }

    if (childList.length == 0) throw 'empty return is currently not supported';
    
    return {
      byType: byType,
      childList: childList,
    }    
  }
  
  public function renderAll(nodes:Array<VNode<Virtual, Real>>):Rendered<Virtual, Real> 
    return _renderAll(nodes, {
      native: function (_, _, v) return create(v),
      widget: function (_, _, a, t) return t.create(a)
    });
  
  public function mountInto(target:Real, nodes:Array<VNode<Virtual, Real>>):Rendered<Virtual, Real> {
    var ret = renderAll(nodes);
    setChildren(target, flatten(ret.childList));
    return ret;
  }

  public function update(before:Rendered<Virtual, Real>, nodes:Array<VNode<Virtual, Real>>, w:Widget<Virtual, Real>) {
    
    for (registry in before.byType)
      registry.each(function (r) switch r {
        case { ref: null }:
        case { ref: f }: f(null);
      });

    function previous(t:NodeType, key:Key)
      return 
        switch before.byType[t] {
          case null: null;
          case v: 
            if (key == null) v.pull();
            else v.get(key);
        }

    var after = _renderAll(nodes, {
      native: function (type, key, nu) return switch previous(type, key) {
        case null: create(nu);
        case { kind: RNative(old, r) }: updateNative(r, nu, old); r;
        default: throw 'assert';
      },
      widget: function (type, key, attr, widgetType) return switch previous(type, key) {
        case null: widgetType.create(attr);
        case { kind: RWidget(w) }: widgetType.update(attr, w); w;
        default: throw 'assert';
      },
    });   

    for (registry in before.byType)
      registry.each(function (r) switch r.kind {
        case RWidget(w): @:privateAccess w._coco_teardown();
        default:
      });

    var before = flatten(before.childList);
    switch nativeParent(before[0]) {
      case null:
      case parent:
        spliceChildren(parent, flatten(after.childList), before[0], before.length);
    }

    return after;
  }

  function nativeParent(real:Real):Null<Real> 
    return throw 'abstract';

  function updateNative(real:Real, nu:Virtual, old:Virtual) 
    throw 'abstract';

  function create(n:Virtual):Real 
    return throw 'abstract';

  function flatten(children):Array<Real> {
    var ret = [];
    function rec(children:Array<RNode<Virtual, Real>>)
      for (c in children) switch c.kind {
        case RNative(_, r): ret.push(r);
        case RWidget(w): rec(@:privateAccess w._coco_getRender().childList);
      }
    rec(children);
    return ret;
  }

  function spliceChildren(target:Real, children:Array<Real>, start:Real, oldCount:Int)
    throw 'abstract';

  function setChildren(target:Real, children:Array<Real>)//TODO: passing the array of children directly may open opportunities for optimization
    throw 'abstract';

  public function teardown(target:Real) 
    setChildren(target, []);
}