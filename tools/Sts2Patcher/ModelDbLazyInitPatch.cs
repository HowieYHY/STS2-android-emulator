using Mono.Cecil;
using Mono.Cecil.Cil;

namespace Sts2Patcher;

/// <summary>
/// Mono (Android) runs a beforefieldinit type's static initialiser as soon as an instance is created;
/// CoreCLR (desktop) waits until a static field is read. Some models fill static fields from ModelDb
/// (e.g. BowlbugsNormal._workerValidCounts uses ModelDb.Monster&lt;BowlbugEgg&gt;()), so on Mono they run in the
/// middle of ModelDb.Init and ask for models that aren't registered yet: KeyNotFoundException at startup.
///
/// Fix: ModelDb.Get&lt;T&gt;() creates and registers a missing model on demand, and Init skips models that
/// already exist. Every model still has exactly one instance; only the creation order can change.
/// </summary>
public sealed class ModelDbLazyInitPatch : IPatch
{
    public string Name => "ModelDb: create models on first request (Mono static-init order)";

    private const string HelperName = "__sts2port_GetOrCreate";

    public void Apply(ModuleDefinition module)
    {
        var modelDb = module.GetType("MegaCrit.Sts2.Core.Models.ModelDb") ?? throw new PatchException("ModelDb type not found");
        if (modelDb.Methods.Any(m => m.Name == HelperName))
            throw new PatchException("already patched (input must be the original sts2.dll)");

        var abstractModel = module.GetType("MegaCrit.Sts2.Core.Models.AbstractModel") ?? throw new PatchException("AbstractModel not found");
        var contentById = modelDb.Fields.SingleOrDefault(f => f.Name == "_contentById" && f.IsStatic)
            ?? throw new PatchException("_contentById field not found");
        var dictType = contentById.FieldType as GenericInstanceType
            ?? throw new PatchException("_contentById is not a generic Dictionary");
        var getIdType = modelDb.Methods.SingleOrDefault(m => m.Name == "GetId" && !m.HasGenericParameters
            && m.Parameters.Count == 1 && m.Parameters[0].ParameterType.FullName == "System.Type")
            ?? throw new PatchException("GetId(Type) not found");
        var getIdGeneric = modelDb.Methods.SingleOrDefault(m => m.Name == "GetId" && m.HasGenericParameters && m.Parameters.Count == 0)
            ?? throw new PatchException("GetId<T>() not found");
        var getT = modelDb.Methods.SingleOrDefault(m => m.Name == "Get" && m.HasGenericParameters && m.Parameters.Count == 0)
            ?? throw new PatchException("Get<T>() not found");
        var init = modelDb.Methods.SingleOrDefault(m => m.Name == "Init" && m.Parameters.Count == 1
            && m.Parameters[0].ParameterType.FullName == "System.Type[]")
            ?? throw new PatchException("Init(Type[]) not found");
        var allSubtypes = modelDb.Properties.SingleOrDefault(p => p.Name == "AllAbstractModelSubtypes")?.GetMethod
            ?? throw new PatchException("AllAbstractModelSubtypes not found");

        // Reuse references the original code already makes, so no new assembly references are added.
        var createInstance = FindCall(init, "System.Activator", "CreateInstance");
        var getTypeFromHandle = FindCall(getIdGeneric, "System.Type", "GetTypeFromHandle");
        var tryGetValue = DictMethod(module, dictType, "TryGetValue", 2);
        var setItem = DictMethod(module, dictType, "set_Item", 2);

        // static AbstractModel __sts2port_GetOrCreate(Type type)
        var helper = new MethodDefinition(HelperName,
            MethodAttributes.Private | MethodAttributes.Static | MethodAttributes.HideBySig, abstractModel);
        helper.Parameters.Add(new ParameterDefinition("type", ParameterAttributes.None, getIdType.Parameters[0].ParameterType));
        var id = new VariableDefinition(getIdType.ReturnType);
        var value = new VariableDefinition(abstractModel);
        var existing = new VariableDefinition(abstractModel);
        helper.Body.Variables.Add(id);
        helper.Body.Variables.Add(value);
        helper.Body.Variables.Add(existing);
        helper.Body.InitLocals = true;
        var il = helper.Body.GetILProcessor();
        var create = Instruction.Create(OpCodes.Ldarg_0);
        var store = Instruction.Create(OpCodes.Ldsfld, contentById);
        il.Emit(OpCodes.Ldarg_0);
        il.Emit(OpCodes.Call, getIdType);
        il.Emit(OpCodes.Stloc, id);
        il.Emit(OpCodes.Ldsfld, contentById);   // fast path: already registered
        il.Emit(OpCodes.Ldloc, id);
        il.Emit(OpCodes.Ldloca, value);
        il.Emit(OpCodes.Callvirt, tryGetValue);
        il.Emit(OpCodes.Brfalse, create);
        il.Emit(OpCodes.Ldloc, value);
        il.Emit(OpCodes.Ret);
        il.Append(create);                       // create it
        il.Emit(OpCodes.Call, createInstance);
        il.Emit(OpCodes.Castclass, abstractModel);
        il.Emit(OpCodes.Stloc, value);
        il.Emit(OpCodes.Ldsfld, contentById);   // its static init may have registered it re-entrantly
        il.Emit(OpCodes.Ldloc, id);
        il.Emit(OpCodes.Ldloca, existing);
        il.Emit(OpCodes.Callvirt, tryGetValue);
        il.Emit(OpCodes.Brfalse, store);
        il.Emit(OpCodes.Ldloc, existing);
        il.Emit(OpCodes.Ret);
        il.Append(store);                        // register it
        il.Emit(OpCodes.Ldloc, id);
        il.Emit(OpCodes.Ldloc, value);
        il.Emit(OpCodes.Callvirt, setItem);
        il.Emit(OpCodes.Ldloc, value);
        il.Emit(OpCodes.Ret);
        modelDb.Methods.Add(helper);

        // Get<T>() => (T)__sts2port_GetOrCreate(typeof(T))
        ReplaceBody(getT, body =>
        {
            var p = body.GetILProcessor();
            p.Emit(OpCodes.Ldtoken, getT.GenericParameters[0]);
            p.Emit(OpCodes.Call, getTypeFromHandle);
            p.Emit(OpCodes.Call, helper);
            p.Emit(OpCodes.Unbox_Any, getT.GenericParameters[0]);
            p.Emit(OpCodes.Ret);
        });

        // Init(Type[] injected) { foreach (var t in injected ?? AllAbstractModelSubtypes) __sts2port_GetOrCreate(t); }
        ReplaceBody(init, body =>
        {
            var arr = new VariableDefinition(init.Parameters[0].ParameterType);
            var i = new VariableDefinition(module.TypeSystem.Int32);
            body.Variables.Add(arr);
            body.Variables.Add(i);
            body.InitLocals = true;
            var p = body.GetILProcessor();
            var have = Instruction.Create(OpCodes.Stloc, arr);
            var cond = Instruction.Create(OpCodes.Ldloc, i);
            var loop = Instruction.Create(OpCodes.Ldloc, arr);
            p.Emit(OpCodes.Ldarg_0);
            p.Emit(OpCodes.Dup);
            p.Emit(OpCodes.Brtrue, have);
            p.Emit(OpCodes.Pop);
            p.Emit(OpCodes.Call, allSubtypes);
            p.Append(have);
            p.Emit(OpCodes.Ldc_I4_0);
            p.Emit(OpCodes.Stloc, i);
            p.Emit(OpCodes.Br, cond);
            p.Append(loop);
            p.Emit(OpCodes.Ldloc, i);
            p.Emit(OpCodes.Ldelem_Ref);
            p.Emit(OpCodes.Call, helper);
            p.Emit(OpCodes.Pop);
            p.Emit(OpCodes.Ldloc, i);
            p.Emit(OpCodes.Ldc_I4_1);
            p.Emit(OpCodes.Add);
            p.Emit(OpCodes.Stloc, i);
            p.Append(cond);
            p.Emit(OpCodes.Ldloc, arr);
            p.Emit(OpCodes.Ldlen);
            p.Emit(OpCodes.Conv_I4);
            p.Emit(OpCodes.Blt, loop);
            p.Emit(OpCodes.Ret);
        });
    }

    private static MethodReference FindCall(MethodDefinition method, string declaringType, string name) =>
        method.Body.Instructions
            .Where(ins => ins.OpCode == OpCodes.Call || ins.OpCode == OpCodes.Callvirt)
            .Select(ins => ins.Operand as MethodReference)
            .FirstOrDefault(m => m != null && m.DeclaringType.FullName == declaringType && m.Name == name)
        ?? throw new PatchException($"{method.Name} no longer calls {declaringType}.{name}");

    /// <summary>A reference to a method of the closed generic Dictionary type (e.g. TryGetValue(!0, out !1)).</summary>
    private static MethodReference DictMethod(ModuleDefinition module, GenericInstanceType dictType, string name, int paramCount)
    {
        var def = dictType.Resolve().Methods.SingleOrDefault(m => m.Name == name && m.Parameters.Count == paramCount)
            ?? throw new PatchException($"Dictionary.{name} not found");
        var r = new MethodReference(def.Name, def.ReturnType, dictType)
        {
            HasThis = def.HasThis,
            ExplicitThis = def.ExplicitThis,
            CallingConvention = def.CallingConvention,
        };
        foreach (var p in def.Parameters)
            r.Parameters.Add(new ParameterDefinition(p.ParameterType));
        return module.ImportReference(r);
    }

    private static void ReplaceBody(MethodDefinition method, Action<MethodBody> emit)
    {
        method.Body = new MethodBody(method);
        emit(method.Body);
    }
}
